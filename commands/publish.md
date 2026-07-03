---
description: Emit the publishable set into the public staging repo — allowlist-manifest-driven, deterministic, leak-gated, lands as a PR.
---

# /publish — emit the publishable set (builder-side)

Run **from a Brainforge checkout**. The publishable set is declared in `plugin.json`'s `publish`
block — allowlist `include` globs copied verbatim, `map` renames for the authored public variants
(`*.public.md`), and a leak denylist in `publish-audit.json` (private — matched by no include glob).
Anything not matched is **private by default**.
This is DESIGN §6's "package as B" made real: what is public is auditable code, not memory.

**Arguments:** none (the seam is the manifest). Optional: `--land` to push + open the PR
(default is a dry run), `--repo <url-or-slug>` to override the staging remote (proof harnesses
only — never for a real publish).

## 0. Guards — before any write

1. **You are in Brainforge:** `.claude-plugin/plugin.json` with a `publish` block exists here.
2. **Clean tree:** publish only from a commit — the emitted tree must be reproducible from a SHA.
3. **Corollary rule:** touching any published path means re-running `/publish` before the next
   release. The short-circuit makes a no-change run free.

Forks: `publish-audit.json` is deliberately not published — author your own denylist before
first `/publish` (the `NO-AUDIT-FILE` abort is pointing at this).

## 1. The script is the contract

Save the script below to a scratch file (e.g. `bf-publish.py`) and run it — dry run first, read
the `DELTA` lines, then `--land`. Zero LLM judgment in the write path; humans decide only at
aborts and in the PR.

```python
#!/usr/bin/env python3
"""Brainforge /publish — deterministic assemble → audit → diff → land. Zero judgment in the write path.
Usage: python3 bf-publish.py <brainforge-checkout> [--land] [--repo <url-or-slug>]"""
import json, hashlib, re, shutil, subprocess, sys, tempfile, pathlib

BF = pathlib.Path(sys.argv[1]).resolve()
LAND = "--land" in sys.argv[2:]
REPO_OVERRIDE = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else None
MANIFEST = ".claude-plugin/plugin.json"

def die(msg): print(msg); sys.exit(1)
def run(*cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0: die(f"CMD-FAILED\t{' '.join(cmd)}\n{r.stderr.strip()}")
    return r.stdout.strip()

plug = json.loads((BF / MANIFEST).read_text())
V = plug["version"]
PUB = plug.get("publish") or die("NO-PUBLISH-BLOCK\tplugin.json has no publish block")
REPO = REPO_OVERRIDE or PUB["repo"]
INC, MAP = PUB["include"], PUB["map"]

# 1. preflight — fail loud, pre-write
if run("git", "-C", str(BF), "status", "--porcelain"):
    die("DIRTY-TREE\tcommit or stash first — publish only from a commit")
missing = [s for s in MAP if not (BF / s).is_file()]
if missing: die("MAP-MISSING\t" + "\t".join(missing))
if not (BF / "LICENSE").is_file(): die("NO-LICENSE\tLICENSE missing at repo root")
apath = BF / "publish-audit.json"
if not apath.is_file(): die("NO-AUDIT-FILE\tpublish-audit.json missing at repo root")
AUD = json.loads(apath.read_text())
def under(rel, g): return rel == g or (g.endswith("/**") and rel.startswith(g[:-2]))
files = [str(p.relative_to(BF)) for p in sorted(BF.rglob("*"))
         if p.is_file() and ".git" not in p.parts]
inc_matches = {g: [f for f in files if under(f, g)] for g in INC}
empty = [g for g, m in inc_matches.items() if not m]
if empty: die("EMPTY-GLOB\t" + "\t".join(empty))

# 2. assemble — pure copy, allowlist only, ephemeral temp dir
tmp = pathlib.Path(tempfile.mkdtemp(prefix="bf-publish-"))
out = tmp / "assembled"
for m in inc_matches.values():
    for f in m:
        dst = out / f; dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(BF / f, dst)
for src, dst_rel in MAP.items():
    dst = out / dst_rel; dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(BF / src, dst)

# 3. leak tripwire — grep the assembled tree, minus per-file exceptions. The denylist itself lives in publish-audit.json, which no include glob matches — private by design.
exc = {(e["file"], e["pattern"]) for e in AUD.get("exceptions", [])}
hits, skipped = [], []
for p in sorted(out.rglob("*")):
    if not p.is_file(): continue
    rel = str(p.relative_to(out))
    try: text = p.read_text()
    except UnicodeDecodeError: skipped.append(f"AUDIT-SKIPPED-BINARY\t{rel}"); continue
    for pat in AUD.get("patterns", []):
        if (rel, pat) in exc: continue
        for i, line in enumerate(text.splitlines(), 1):
            if re.search(pat, line): hits.append(f"{rel}:{i}\t{pat}\t{line.strip()[:120]}")
for s in skipped: print(s)
if hits:
    print("LEAK-TRIPWIRE\taborting — nothing pushed; a human decides each line:")
    [print(h) for h in hits]; sys.exit(1)

# 4. short-circuit — the staging repo IS the state (golden rule #1)
clone = tmp / "staging"
url = REPO if ("://" in REPO or REPO.startswith("git@")) else f"https://github.com/{REPO}.git"
run("git", "clone", url, str(clone))
def tree(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob("*")) if p.is_file() and ".git" not in p.parts}
A, S = tree(out), tree(clone)
if A == S: print(f"UP-TO-DATE\tv{V} — staging matches, zero writes"); sys.exit(0)
for f in sorted(set(A) | set(S)):
    if f not in S: print(f"ADD\t{f}")
    elif f not in A: print(f"DELETE\t{f}")
    elif A[f] != S[f]: print(f"CHANGE\t{f}")
if not LAND:
    print(f"DELTA\tassembled at {out} differs from staging — rerun with --land to open the PR")
    sys.exit(0)

# 5. land — branch, replace, commit, push, PR; never main, never a direct write
shortsha = run("git", "-C", str(BF), "rev-parse", "--short", "HEAD")
branch = f"publish/v{V}-{shortsha}"
run("git", "-C", str(clone), "checkout", "-b", branch)
for p in clone.iterdir():
    if p.name == ".git": continue
    shutil.rmtree(p) if p.is_dir() else p.unlink()
shutil.copytree(out, clone, dirs_exist_ok=True)
run("git", "-C", str(clone), "add", "-A")   # safe: the clone contains ONLY the assembled tree
run("git", "-C", str(clone), "commit", "-m", f"publish: v{V} from brainforge {shortsha}")
run("git", "-C", str(clone), "push", "-u", "origin", branch)
print(f"PUSHED\t{branch}")
pr = subprocess.run(["gh", "pr", "create", "--repo", REPO, "--head", branch,
    "--title", f"Publish v{V} ({shortsha})",
    "--body", f"Publishable set emitted from brainforge `{shortsha}` by `/publish`.\n"
              f"Review as a stranger; merge = release."], capture_output=True, text=True)
print(f"PR\t{pr.stdout.strip()}" if pr.returncode == 0
      else f"PR-CREATE-SKIPPED\t{(pr.stderr.strip().splitlines() or ['no gh / non-GitHub remote'])[-1]}")
```

## 2. Reading the output

| Tag | Meaning |
|---|---|
| `DIRTY-TREE` / `MAP-MISSING` / `NO-LICENSE` / `EMPTY-GLOB` / `NO-AUDIT-FILE` | Preflight abort — nothing assembled. Fix and re-run. |
| `AUDIT-SKIPPED-BINARY` | Transparency lines — files the tripwire cannot grep. |
| `LEAK-TRIPWIRE` + `file:line` lines | Abort — a denylisted pattern reached the assembled tree. Fix the file, or add a per-file exception **only** if the mention is legitimately public. |
| `UP-TO-DATE` | Staging already matches this commit's publishable set. Zero writes. |
| `ADD`/`CHANGE`/`DELETE` + `DELTA` | Dry run: what `--land` would ship. |
| `PUSHED` + `PR` | Landed. Review the PR as a stranger; merge = release. |
| `PR-CREATE-SKIPPED` | Branch pushed but no PR (no `gh`, or non-GitHub remote — proof harnesses). |

## Never

- Never push to the staging repo's `main` — every landing is a `publish/v<version>-<shortsha>`
  branch + PR, and merging is a human act.
- Never weaken an audit pattern globally — exceptions are per-file + per-pattern, added only for
  legitimately-public mentions (today: `DESIGN.md`'s origin story).
- Never edit the private `README.md`/`DESIGN.md`/`ROADMAP.md` to make them publishable — the
  public variants are separately authored `*.public.md` files.
- Never publish from a dirty tree, and never run `--repo` overrides against the real staging repo.
- Never auto-merge the publish PR.
- Never add `publish-audit.json` to the `include` globs — the denylist must never ship with the
  set it polices.
