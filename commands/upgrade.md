---
description: Upgrade a scaffolded brain's vendored runtime to this checkout's version — manifest-guarded, deterministic, lands as a PR.
---

# /upgrade — re-emit a brain's runtime (builder-side)

Run **from a Brainforge checkout, against a brain checkout**. The brain ships zero upgrade
machinery — this command and `scaffold/` are the source; only `.brainforge/runtime-manifest.json`
lives brain-side. This is DESIGN §1's promise made real: tooling upgrades come down as
regenerated files **via PR**, and the brain stays a self-sufficient repo.

**Arguments:** `$ARGUMENTS` — path to the brain checkout (ask if missing; always quote it — brain
paths may contain spaces).

## 0. Guards — all four before any write

1. **You are in Brainforge:** `.claude-plugin/plugin.json` and `scaffold/` exist here.
2. **The target is a brain:** `<brain>/sources.json` exists (the `/forge` guard — never run against
   an arbitrary directory).
3. **The brain working tree is clean:** `git -C "<brain>" status --porcelain` is empty — otherwise
   stop and ask the user to commit or stash first.
4. **Confirm the template map:** `{{ORG}}` = the org name in the H1 of the brain's `README.md`
   (`# <ORG> — Shared Context`). **Confirm the inferred value with the user before emitting** — a
   wrong map makes every hash comparison wrong.

## 1. The seam + the cheap gate (golden rule #1)

Read `plugin.json` → version `V` and the `runtime.bump` globs. **The globs are the seam — never
hardcode paths.** Then read `<brain>/.brainforge/runtime-manifest.json` and route:

| Manifest state | Route |
|---|---|
| `runtime-version` == `V` | Say **"up to date (v`V`)"** and STOP — zero file work. |
| `runtime-version` newer than `V` | STOP — this Brainforge checkout is stale; pull it first. |
| file missing or malformed | **Adoption pass** — never guess a baseline. |
| older than `V` | **Steady-state pass**. |

## 2. Emit = copy + template — never a raw copy

`emitted(f)` = the scaffold file with `{{ORG}}` substituted using the confirmed map. Every hash —
in the manifest and in every comparison below — is `sha256(emitted bytes)`. Substitution is
deterministic; the only judgment allowed anywhere near the write path is the user confirming the
org name in guard 4.

## 3. Classify + apply — the script is the contract

Save the script below to a scratch file (e.g. `bf-upgrade.py`) and run it. Dry run first, then
`--apply` **on the upgrade branch** (§6). It prints one `ACTION<TAB>file` line per file:

| Action | Meaning | Writes |
|---|---|---|
| `OVERWRITE` | shipped, byte-unmodified vs baseline, changed upstream or not | emit new version |
| `ADD` | new upstream file, absent from the brain | emit |
| `ADOPT-CLEAN` | byte-matches the current shipped version — provably stock | manifest entry only, nothing to disk |
| `DELETE-SUPERSEDED` | in manifest, gone upstream, byte-unmodified | delete |
| `FLAG-MODIFIED` | shipped but locally modified | none — PR body, with pointer to the new shipped version; **baseline kept in the manifest** |
| `FLAG-SUPERSEDED-MODIFIED` | gone upstream but locally modified | none — PR body; baseline kept |
| `FLAG-COLLISION` | consumer file sits where a *new* shipped file landed | none — PR body; never overwrite consumer work |
| `FLAG-CONSUMER-DELETED` | in manifest, missing on disk | none — not resurrected; dropped from the manifest |
| `FLAG-UNVERIFIABLE-DIFFERS` | adoption pass: differs from the current shipped version, no baseline | none — reconcile by hand in the PR |
| `FLAG-UNVERIFIABLE-UNSHIPPED` | adoption pass: under a bump glob but not currently shipped (legacy runtime, or yours) | none — reconcile by hand in the PR |
| `LIST-CONSUMER` | yours (steady-state: not shipped, not in manifest) | none — listed for transparency |

**Load-bearing for `/forge`:** `commands/forge.md` §3 extracts exactly this fence
(`awk '/^```python$/,/^```$/'` — it must remain the FIRST ```python block in this file) and calls
the script with this CLI signature; keep both stable or the fresh-install bootstrap silently
breaks.

```python
#!/usr/bin/env python3
"""Brainforge /upgrade — deterministic classify + apply. Zero judgment in the write path.
Usage: python3 bf-upgrade.py <brainforge-checkout> <brain-checkout> <ORG> [--apply]"""
import json, hashlib, subprocess, sys, pathlib

BF, BRAIN, ORG = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
APPLY = "--apply" in sys.argv[4:]
SCAF = BF / "scaffold"
plug = json.loads((BF / ".claude-plugin" / "plugin.json").read_text())
V, BUMP = plug["version"], plug["runtime"]["bump"]

def vt(v): return tuple(int(x) for x in v.split("."))
def under(rel, globs):
    return any(rel == g or (g.endswith("/**") and rel.startswith(g[:-2])) for g in globs)
def emit_bytes(p):  # emit = copy + template, never a raw copy
    return p.read_bytes().replace(b"{{ORG}}", ORG.encode())
def sha(b): return "sha256:" + hashlib.sha256(b).hexdigest()
def tree(root, xform):
    return {str(p.relative_to(root)): sha(xform(p)) for p in sorted(root.rglob("*"))
            if p.is_file() and ".git" not in p.parts and under(str(p.relative_to(root)), BUMP)}

mpath = BRAIN / ".brainforge" / "runtime-manifest.json"
try:
    m = json.loads(mpath.read_text()); M = dict(m["files"]); MV = m["runtime-version"]; vt(MV)
except Exception:
    M, MV = None, None  # missing/malformed → adoption pass; never guess a baseline

if MV is not None:
    if vt(MV) == vt(V): print(f"UP-TO-DATE\t{V}"); sys.exit(0)
    if vt(MV) > vt(V):  print(f"STALE-CHECKOUT\tbrain has {MV}, checkout ships {V} — pull Brainforge first"); sys.exit(1)

S = tree(SCAF, emit_bytes)                      # shipped, as-emitted
B = tree(BRAIN, lambda p: p.read_bytes())       # brain, on disk

acts, newman = {}, {}
if M is None:                                   # ADOPTION PASS — overwrite NOTHING, delete NOTHING
    for f in sorted(set(S) | set(B)):
        if f not in B:        acts[f] = "ADD";                        newman[f] = S[f]
        elif f not in S:      acts[f] = "FLAG-UNVERIFIABLE-UNSHIPPED"
        elif B[f] == S[f]:    acts[f] = "ADOPT-CLEAN";                newman[f] = S[f]
        else:                 acts[f] = "FLAG-UNVERIFIABLE-DIFFERS"
else:                                           # STEADY-STATE PASS — pure set logic
    for f in sorted(set(S) | set(B) | set(M)):
        inS, inB, inM = f in S, f in B, f in M
        if inS and inB and inM:
            if B[f] == M[f]:  acts[f] = "OVERWRITE";                  newman[f] = S[f]
            else:             acts[f] = "FLAG-MODIFIED";              newman[f] = M[f]
        elif inS and inB:
            if B[f] == S[f]:  acts[f] = "ADOPT-CLEAN";                newman[f] = S[f]
            else:             acts[f] = "FLAG-COLLISION"
        elif inS and inM:     acts[f] = "FLAG-CONSUMER-DELETED"       # dropped from manifest
        elif inS:             acts[f] = "ADD";                        newman[f] = S[f]
        elif inB and inM:
            if B[f] == M[f]:  acts[f] = "DELETE-SUPERSEDED"
            else:             acts[f] = "FLAG-SUPERSEDED-MODIFIED";   newman[f] = M[f]
        elif inB:             acts[f] = "LIST-CONSUMER"
        # in M only (gone both sides): dropped from the manifest silently

for f, a in sorted(acts.items(), key=lambda kv: kv[1]): print(f"{a}\t{f}")

if APPLY:
    for f, a in acts.items():
        if a in ("OVERWRITE", "ADD"):
            dst = BRAIN / f; dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(emit_bytes(SCAF / f))
        elif a == "DELETE-SUPERSEDED":
            (BRAIN / f).unlink()
    sha_bf = subprocess.run(["git", "-C", str(BF), "rev-parse", "HEAD"],
                            capture_output=True, text=True).stdout.strip()
    mpath.parent.mkdir(parents=True, exist_ok=True)
    mpath.write_text(json.dumps({"runtime-version": V, "emitted-from": sha_bf,
                                 "files": newman}, indent=2) + "\n")
    print(f"APPLIED\tmanifest -> {V} ({len(newman)} files)")
```

**Manifest rewrite rules (encoded above, restated):** emitted files (`OVERWRITE`/`ADD`) and
byte-match adoptions get the new shipped hash; `FLAG-MODIFIED`/`FLAG-SUPERSEDED-MODIFIED` keep
their **old** baseline entry so the next upgrade still knows their true baseline; consumer files
and collisions stay out of the manifest; `FLAG-CONSUMER-DELETED` and gone-both-sides entries are
dropped.

**Scaffold-time bootstrap:** on a freshly copied + templated brain, run the same script (no
manifest yet → adoption pass → every bump file is `ADOPT-CLEAN`) with `--apply`. That writes the
birth manifest — the emission contract in one command.

## 4. Superseded files (`runtime.remove`)

For each brain-relative path in `runtime.remove`: if the file is absent, skip. If present and
its hash matches `.brainforge/runtime-manifest.json` (unmodified since emit), delete it in the
upgrade PR — it has been renamed/superseded by this runtime version. If present but modified,
do NOT delete: flag it in the PR body (`superseded but locally modified — remove by hand`).
A brain must never end up answering to both the old and new name of the same command.

After applying removals, grep the brain's `once` paths (`README.md`, `CLAUDE.md`,
`templates/**`) for the bare command name(s) being removed (e.g. `/walk`) and list every hit
in the upgrade PR body as a "hand-edit needed" checklist — **never auto-edit a `once` path**,
those are consumer-owned. Pre-0.4.0 brains predate `templates/brain-pointer-snippet.md`; since
`once` paths are never re-emitted, their owners should manually copy it in from the plugin.

## 5. Ref-scan (both passes)

After applying, scan the brain's markdown for runtime-path references and check each still exists:

```bash
grep -rnoE '(pipeline|\.claude/commands|authoring|setup)/[A-Za-z0-9._/-]+\.(md|json)' \
  --include='*.md' "<brain>" 2>/dev/null | grep -v '/\.git/' | grep -v 'context/derived/' | sort -u
```

For every referenced path that does **not** exist on disk after the apply — plus every reference
to a file this run flagged or deleted — add a checklist line to the PR body (file:line →
missing/flagged target). Fixing them is human work inside the PR (the generalized Shopify lesson:
stale `/sync` dispatch pointers are exactly what humans miss).

## 6. Land as a PR (golden rule #4) — never a direct write

All writes happen on a branch: `git -C "<brain>" checkout -b upgrade/runtime-<V>` **before**
`--apply`. Stage only the emitted paths + the manifest — **never a blanket `git add -A`** — so a
brain's untracked local files (e.g. Claude Code's per-user `.claude/settings.local.json`) never
ride into the PR. Commit, push, open the PR with this body shape:

```markdown
## Runtime upgrade → v<V>
Emitted from Brainforge `<emitted-from SHA>`.

### Overwritten (clean) / Added / Adopted (byte-match) / Deleted (superseded)
- <file> — <action>

### ⚠️ Flagged — human reconciliation needed in this PR
- [ ] <file> — <flag reason>; shipped version: `scaffold/<file>` @ <SHA>

### Ref-scan — stale runtime pointers
- [ ] <file>:<line> → references `<missing/flagged path>`

### Hand-edit needed — superseded command names in `once` paths
- [ ] <file>:<line> → still references `<removed command name>`

### Yours, untouched
- <file>
```

Any abort before push leaves the brain's `main` untouched. Re-running is idempotent: same inputs,
same set logic, same result.

## Never

- Never touch `context/canon/`, `context/derived/`, `sources.json`, `.sync-state.json`, `.env*`,
  or any `once` path — the script only writes under bump globs plus the manifest, and nothing else
  may either.
- Never overwrite a file whose hash differs from its manifest baseline, and never touch a
  consumer-added file — flag, don't clobber.
- Never merge content (no LLM-mediated three-way merges) — byte-exact set logic only; humans
  reconcile flags in the PR.
- Never resurrect a consumer-deleted file.
- Never land except via the PR. Never auto-merge it.
