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
hardcode paths.** Then read `<brain>/.brainforge/runtime-manifest.json` and route.

**First, prove this checkout is not behind.** Every route below compares the brain against *this checkout*,
and a checkout nothing auto-pulls (a plugin marketplace clone, an old laptop copy) can be behind
while still shipping the brain's own version. Then `runtime-version == V` and the table says "up
to date" to a brain that is several versions behind: the most reassuring output this command has,
and the least earned. So whenever the brain has a manifest, the §3 script checks the checkout
before routing, and refuses rather than guess:

| Checkout | Check | Refuses with |
|---|---|---|
| git, clean (`BF` is the repo root) | `git fetch origin`, then `git rev-list --count HEAD..origin/HEAD` (else `origin/main`) | `STALE-CHECKOUT` when that count is above 0: pull, or rebase a feature branch, then re-run |
| git, **dirty** (tracked changes) | none, **refused** | `DIRTY-CHECKOUT`: the manifest would record a commit whose bytes differ from what was emitted |
| git, **detached** | **allowed**, same fetch and count against origin's default branch | `STALE-CHECKOUT` only if that branch has commits HEAD lacks |
| not git (the installed plugin copy), or inside some other repo | reads the published `plugin.json` at `repository` and compares **versions only** | `STALE-CHECKOUT` when the published version is newer: update the plugin, then re-run |
| no `origin`, fetch fails (offline, or needs credentials: git never prompts here), no `repository` | none possible | `UNVERIFIED-CHECKOUT`. Never a bare "up to date" |

It compares against `origin`. A fork whose `origin` is the fork passes while behind the canonical
repo; point `origin` at the repo you publish from. The non-git path cannot see a change shipped
without a version bump; the `UNBUMPED-CHANGE` route below exists for exactly that, and it only
works from a checkout that has the change.

Untracked files do not count as dirty, so the scratch `bf-upgrade.py` can live in the checkout.
The check is skipped only when the brain has no manifest (the adoption pass), which is how
`/forge`'s bootstrap runs offline against a tree it just emitted from the same checkout.

| Manifest state | Route |
|---|---|
| `runtime-version` == `V`, every shipped bump file matches its baseline hash | Say **"up to date (v`V`)"** and STOP — zero file work. |
| `runtime-version` == `V`, some shipped bump file differs from its baseline | Changes shipped without a version bump: the script prints `UNBUMPED-CHANGE` — run the **steady-state pass**. |
| `runtime-version` newer than `V` | STOP — this Brainforge checkout is stale; pull it first. (Unpulled commits are caught above, before this table.) |
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
| `FLAG-CONSUMER-DELETED` | in manifest, missing on disk | none — not resurrected; **tombstoned** (`null`) in the manifest |
| `LIST-CONSUMER-DELETED` | tombstoned by an earlier upgrade, still absent | none — the deletion is remembered, never re-added |
| `FLAG-UNVERIFIABLE-DIFFERS` | adoption pass: differs from the current shipped version, no baseline | none — reconcile by hand in the PR |
| `FLAG-UNVERIFIABLE-UNSHIPPED` | adoption pass: under a bump glob but not currently shipped (legacy runtime, or yours) | none — reconcile by hand in the PR |
| `SUPERSEDED-FLAG` | listed in `runtime.remove`, present, but no manifest baseline proves it unmodified | none — remove by hand, listed in the PR body |
| `SUPERSEDED-REFUSED` | listed in `runtime.remove` but brain-owned — a `once` path, or anything under `context/` | none — the deletion is refused and the misconfigured `remove` entry is listed in the PR body |
| `LIST-CONSUMER` | yours (steady-state: not shipped, not in manifest) | none — listed for transparency |

**Load-bearing for `/forge`:** `commands/forge.md` §3 extracts exactly this fence
(`awk '/^```python$/,/^```$/'` — it must remain the ONLY ```python block in this file, because
that awk range joins every python fence it finds into one script) and calls the script with this
CLI signature; keep both stable or the fresh-install bootstrap silently breaks.

```python
#!/usr/bin/env python3
"""Brainforge /upgrade — deterministic classify + apply. Zero judgment in the write path.
Usage: python3 bf-upgrade.py <brainforge-checkout> <brain-checkout> <ORG> [--apply]"""
import json, hashlib, os, re, subprocess, sys, pathlib, urllib.request

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
    m = json.loads(mpath.read_text()); _F = dict(m["files"]); MV = m["runtime-version"]; vt(MV)
    # null value = TOMBSTONE: shipped once, deleted by the consumer on purpose. Dropping the
    # entry entirely made the NEXT upgrade see a shipped file that is absent and unknown, call
    # it ADD, and write it back -- resurrecting a deletion, against this command's own Never.
    M = {k: v for k, v in _F.items() if v is not None}
    TOMB = {k for k, v in _F.items() if v is None}
except Exception:
    M, MV, TOMB = None, None, set()  # missing/malformed → adoption pass; never guess a baseline

S = tree(SCAF, emit_bytes)                      # shipped, as-emitted

def checkout_current():
    """Prove this checkout is not behind before routing on V (§1 guard). A checkout nothing
    auto-pulls reports "up to date" against its own stale V, the most reassuring output this
    command has and the least earned. Git checkout (BF is itself the repo root): refuse when
    dirty, fetch origin, refuse on commits origin's default branch has and HEAD lacks. Non-git
    copy (the plugin cache): compare V with the published plugin.json at `repository`, versions
    only. Anything unprovable refuses."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_SSH_COMMAND="ssh -oBatchMode=yes")
    def git(*a):   # never prompts: a credential prompt inside a dry run fails fast instead
        try: return subprocess.run(["git", "-C", str(BF), *a], capture_output=True, text=True, timeout=120, env=env)
        except Exception: return subprocess.CompletedProcess(a, 1, "", "")  # no git, or a hung call
    top = git("rev-parse", "--show-toplevel")
    # an enclosing repo (a dotfiles $HOME around the plugin cache) is not this checkout
    if top.returncode == 0 and pathlib.Path(top.stdout.strip()).resolve() == BF.resolve():
        st = git("status", "--porcelain", "--untracked-files=no")
        if st.returncode != 0:
            return "UNVERIFIED-CHECKOUT\tgit status failed in the Brainforge checkout"
        if st.stdout.strip():
            return "DIRTY-CHECKOUT\tuncommitted changes in Brainforge; the manifest would name a commit whose bytes differ. Commit or stash first"
        if git("remote", "get-url", "origin").returncode != 0:
            return "UNVERIFIED-CHECKOUT\tthe Brainforge checkout has no remote named origin to compare against"
        if git("fetch", "--quiet", "origin").returncode != 0:
            return "UNVERIFIED-CHECKOUT\tgit fetch origin failed (offline, or it needs credentials); cannot prove this checkout is current"
        ref = next((r for r in ("origin/HEAD", "origin/main")
                    if git("rev-parse", "--verify", "--quiet", r).returncode == 0), None)
        if ref is None:
            return "UNVERIFIED-CHECKOUT\tno origin/HEAD or origin/main to compare against"
        rl = git("rev-list", "--count", f"HEAD..{ref}")
        if rl.returncode != 0 or not rl.stdout.strip().isdigit():
            return f"UNVERIFIED-CHECKOUT\tcould not count commits between HEAD and {ref}"
        n = int(rl.stdout.strip())
        if n: return f"STALE-CHECKOUT\t{n} commit(s) on {ref} missing from HEAD; pull (or rebase this branch) first"
        return None
    repo = plug.get("repository", "").rstrip("/")
    gh = re.match(r"https://github\.com/([^/]+)/([^/.]+)", repo)
    url = (f"https://raw.githubusercontent.com/{gh[1]}/{gh[2]}/HEAD/.claude-plugin/plugin.json" if gh
           else f"{repo}/.claude-plugin/plugin.json" if repo else None)
    if url is None:
        return "UNVERIFIED-CHECKOUT\tnot a git checkout and plugin.json names no repository"
    try:   # curl first: a python.org python3 on macOS often has no CA bundle, and urllib then fails TLS
        c = subprocess.run(["curl", "-fsSL", "-m", "30", url], capture_output=True, timeout=60)
        body = c.stdout if c.returncode == 0 else None
    except Exception: body = None
    try:
        if body is None:
            with urllib.request.urlopen(url, timeout=30) as r: body = r.read()
        PV = json.loads(body)["version"]; vt(PV)
    except Exception as e:
        return f"UNVERIFIED-CHECKOUT\tcould not read the published version at {url} ({e.__class__.__name__}). Retry online"
    if vt(PV) > vt(V): return f"STALE-CHECKOUT\tpublished {PV}, this copy ships {V}; update the plugin first"
    return None

if MV is not None:
    why = checkout_current()
    if why: print(why); sys.exit(1)
    if vt(MV) == vt(V):
        # A matching version is not proof of matching bytes: a bump-path change shipped without
        # a version bump leaves runtime-version equal. Short-circuit only when every shipped file
        # equals its manifest baseline. A tombstone is a deliberate deletion, not a baseline.
        # Compares hashes only -- emitted-from can be empty or name a commit in another repo.
        drift = [f for f in S if f not in TOMB and M.get(f) != S[f]]
        if not drift: print(f"UP-TO-DATE\t{V}"); sys.exit(0)
        print(f"UNBUMPED-CHANGE\t{V}\t{len(drift)} file(s)")
    if vt(MV) > vt(V):  print(f"STALE-CHECKOUT\tbrain has {MV}, checkout ships {V} — pull Brainforge first"); sys.exit(1)

B = tree(BRAIN, lambda p: p.read_bytes())       # brain, on disk

acts, newman = {}, {}
if M is None:                                   # ADOPTION PASS — overwrite NOTHING, delete NOTHING
    for f in sorted(set(S) | set(B)):
        if f not in B:        acts[f] = "ADD";                        newman[f] = S[f]
        elif f not in S:      acts[f] = "FLAG-UNVERIFIABLE-UNSHIPPED"
        elif B[f] == S[f]:    acts[f] = "ADOPT-CLEAN";                newman[f] = S[f]
        else:                 acts[f] = "FLAG-UNVERIFIABLE-DIFFERS"
else:                                           # STEADY-STATE PASS — pure set logic
    for f in sorted(set(S) | set(B) | set(M) | TOMB):
        if f in TOMB and f not in B:      # still deleted, still deliberate — never re-add
            acts[f] = "LIST-CONSUMER-DELETED"; newman[f] = None; continue
        inS, inB, inM = f in S, f in B, f in M
        if inS and inB and inM:
            if B[f] == M[f]:  acts[f] = "OVERWRITE";                  newman[f] = S[f]
            else:             acts[f] = "FLAG-MODIFIED";              newman[f] = M[f]
        elif inS and inB:
            if B[f] == S[f]:  acts[f] = "ADOPT-CLEAN";                newman[f] = S[f]
            else:             acts[f] = "FLAG-COLLISION"
        elif inS and inM:     acts[f] = "FLAG-CONSUMER-DELETED";      newman[f] = None  # tombstoned
        elif inS:             acts[f] = "ADD";                        newman[f] = S[f]
        elif inB and inM:
            if B[f] == M[f]:  acts[f] = "DELETE-SUPERSEDED"
            else:             acts[f] = "FLAG-SUPERSEDED-MODIFIED";   newman[f] = M[f]
        elif inB:             acts[f] = "LIST-CONSUMER"
        # in M only (gone both sides): dropped from the manifest silently

# runtime.remove — superseded paths, independent of the bump globs. Runs last so it wins.
# Delete only with a manifest baseline proving the file is unmodified since emit; otherwise
# flag for hand removal. Never earns a manifest entry.
ONCE = plug["runtime"].get("once", [])
for f in plug["runtime"].get("remove", []):
    p = BRAIN / f
    if not p.exists():                                 continue
    # brain-owned paths are never deletable, whatever the config says — and never skipped
    # quietly either: a remove entry that names one is a misconfiguration the operator must see
    if under(f, ONCE) or f.startswith("context/"):     acts[f] = "SUPERSEDED-REFUSED"
    elif M and f in M and sha(p.read_bytes()) == M[f]: acts[f] = "DELETE-SUPERSEDED"
    else:                                              acts[f] = "SUPERSEDED-FLAG"
    newman.pop(f, None)

for f, a in sorted(acts.items(), key=lambda kv: kv[1]): print(f"{a}\t{f}")

if APPLY:
    for f, a in acts.items():
        if a in ("OVERWRITE", "ADD"):
            dst = BRAIN / f; dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(emit_bytes(SCAF / f)); dst.chmod((SCAF / f).stat().st_mode)
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
their **old** baseline entry so the next upgrade still knows their true baseline, until a human
reconciles one and re-baselines it (below); consumer files
and collisions stay out of the manifest; `FLAG-CONSUMER-DELETED` is written as a **`null`
tombstone** and stays one while the file is absent, so a deliberate deletion survives every
later upgrade; gone-both-sides entries are dropped. Re-creating a tombstoned file by hand clears
the tombstone and it is classified normally from then on.

### Upstream delta for a flagged file

A `FLAG-MODIFIED` file needs a human to bring upstream changes into their local version. The
baseline is what says which upstream changes those are: it is the hash of the shipped version the
local file was last level with. For each flagged file, run this read-only step. It finds the newest
commit in this checkout whose emitted `scaffold/<file>` matches the baseline, and diffs that
version against HEAD:

```bash
BF="<brainforge-checkout>"; BRAIN="<brain>"; ORG="<ORG>"; F="<flagged file, brain-relative>"
python3 - "$BF" "$BRAIN" "$ORG" "$F" <<'PY'
import hashlib, json, pathlib, subprocess, sys
BF, BRAIN, ORG, F = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
def sha(b): return "sha256:" + hashlib.sha256(b).hexdigest()
def git(*a): return subprocess.run(["git", "-C", str(BF), *a], capture_output=True)
base = json.loads((BRAIN / ".brainforge" / "runtime-manifest.json").read_text())["files"].get(F)
path = f"scaffold/{F}"
if base is None: sys.exit(f"NO-BASELINE\t{F}: not in the manifest")
head, log = git("show", f"HEAD:{path}"), git("log", "--format=%H", "HEAD", "--", path)
if head.returncode != 0 or log.returncode != 0:
    print(f"BASE-UNKNOWN\t{F}: no git history here for {path}; reconcile against the whole shipped file"); sys.exit(0)
for c in log.stdout.decode().split():
    blob = git("show", f"{c}:{path}")
    if blob.returncode == 0 and sha(blob.stdout.replace(b"{{ORG}}", ORG.encode())) == base:
        if blob.stdout == head.stdout:
            print(f"NO-UPSTREAM-CHANGE\t{F}\tsince {c[:7]}: the difference is local; nothing upstream to bring in"); sys.exit(0)
        print(f"UPSTREAM-CHANGED\t{F}\tsince {c[:7]}:", flush=True)
        subprocess.run(["git", "-C", str(BF), "--no-pager", "diff", c, "HEAD", "--", path]); sys.exit(0)
print(f"BASE-UNKNOWN\t{F}: no commit in this checkout ships the baseline; reconcile against the whole shipped file")
PY
```

Its first line goes on the file's line in the PR body's flagged section; an `UPSTREAM-CHANGED`
diff is what the reviewer reconciles. A `NO-UPSTREAM-CHANGE` file still flags, because the
classifier compares bytes and a file with local additions always differs from its baseline, but
there is nothing to reconcile and the PR says so.

### Re-baseline a reconciled file

`FLAG-MODIFIED` keeps the old baseline because the classifier cannot know whether anyone has dealt
with the upstream change. While nobody has, that is right: the delta above shows everything
upstream did since the local file was last level with it. Once a human has reconciled it, the old
baseline is wrong. At the next version the delta starts from a baseline versions old and
re-presents upstream changes already brought in. After a few rounds, people stop reading the
flagged section, which is the one section of the PR that has to be read.

So after reconciling a `FLAG-MODIFIED` file by hand, re-stamp its manifest entry to the current
shipped hash, **and only while the file still differs from shipped.** The step writes the shipped
hash, never the file's own, and refuses when the two are equal, so a baseline never equals a
touched file's on-disk bytes. That equality is what the classifier reads as "byte-unmodified,
safe to overwrite". A file identical to shipped carries no local changes, so this step does not
apply to it. Run it on the upgrade branch after `--apply`, with the same checkout, once per
reconciled file, and stage the manifest with the reconciled file:

```bash
BF="<brainforge-checkout>"; BRAIN="<brain>"; ORG="<ORG>"; F="<reconciled file, brain-relative>"
python3 - "$BF" "$BRAIN" "$ORG" "$F" <<'PY'
import hashlib, json, pathlib, sys
BF, BRAIN, ORG, F = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
def sha(b): return "sha256:" + hashlib.sha256(b).hexdigest()
V = json.loads((BF / ".claude-plugin" / "plugin.json").read_text())["version"]
mp = BRAIN / ".brainforge" / "runtime-manifest.json"; m = json.loads(mp.read_text())
src, dst = BF / "scaffold" / F, BRAIN / F
if m.get("runtime-version") != V:  sys.exit(f"REFUSED\t{F}: manifest is {m.get('runtime-version')}, checkout ships {V}; --apply this upgrade first")
if m["files"].get(F) is None:      sys.exit(f"REFUSED\t{F}: no baseline in the manifest; only a FLAG-MODIFIED file is re-baselined")
if not src.is_file():              sys.exit(f"REFUSED\t{F}: not shipped by this checkout; nothing to re-baseline to")
if not dst.is_file():              sys.exit(f"REFUSED\t{F}: not in the brain")
shipped = sha(src.read_bytes().replace(b"{{ORG}}", ORG.encode()))
if sha(dst.read_bytes()) == shipped:
    sys.exit(f"REFUSED\t{F}: identical to shipped; a baseline equal to its bytes would let the next upgrade overwrite it unflagged")
if m["files"][F] == shipped:       print(f"UNCHANGED\t{F}: already baselined at {V}"); sys.exit(0)
m["files"][F] = shipped
mp.write_text(json.dumps(m, indent=2) + "\n")
print(f"REBASELINED\t{F}\t{V}")
PY
```

It is a documented human step, never part of the script above: only the person who reconciled
the file knows it was reconciled. A re-baselined file still flags on every later upgrade, for the
byte reason above. What changes is its delta: from `V` on, it reports `NO-UPSTREAM-CHANGE` until
upstream edits the file again, and then only the edits made after `V`. Mark it in the PR body's
flagged section as checked: `- [x] <file> — reconciled; re-baselined to v<V>`.

**Scaffold-time bootstrap:** on a freshly copied + templated brain, run the same script (no
manifest yet → adoption pass → every bump file is `ADOPT-CLEAN`) with `--apply`. That writes the
birth manifest — the emission contract in one command.

## 4. Superseded files (`runtime.remove`)

The classifier walks `runtime.remove` directly, **independent of the bump globs** — a superseded
path that sits outside every bump glob is invisible to the set logic, and this pass is the only
thing that sees it. It runs last, so it wins over any bump classification for the same path.

For each brain-relative path in `runtime.remove`:

- **Absent** → skip.
- **Present, and brain-owned** — a `runtime.once` path, or anything under `context/` →
  `SUPERSEDED-REFUSED`. Never deleted, whatever the hash says. Canon, derived context, and the
  `once` files are the brain's own work, and no runtime upgrade may remove them. It is reported
  rather than skipped so a `remove` entry that names one is visible as the misconfiguration it is,
  instead of quietly doing nothing.
- **Present, and its hash matches `.brainforge/runtime-manifest.json`** (unmodified since emit) →
  `DELETE-SUPERSEDED`, deleted in the upgrade PR. It has been renamed or superseded by this
  runtime version.
- **Present, but no manifest baseline proves it unmodified** — either locally modified, or an
  adoption pass with no manifest at all → `SUPERSEDED-FLAG`. Never deleted. It gets a hand-removal
  line in the PR body (`superseded but unverifiable — remove by hand`), because deleting a file we
  cannot prove is untouched would destroy consumer work.

Neither a `SUPERSEDED-FLAG` nor a `SUPERSEDED-REFUSED` path earns a manifest entry, so the next
upgrade does not adopt either as a baseline. The adoption-pass branch matters most: old brains that
still answer to `/walk` are exactly the brains with no manifest, and before this pass existed they
were told nothing.
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

A path that still exists can still point at a section that does not. Check every
`<path> § <section>` reference whose path is in the same runtime-path set: a numbered section
(`§1a`, `§0a-bis`) must match a heading `^#+ +<n>\.`, a named one (`§ Defaults`) a heading
`^#+ +<Word>`. Set `BRAIN` to the brain checkout and `ACTIONS` to a file holding the `--apply`
run's output from §3 (e.g. `python3 bf-upgrade.py … --apply | tee bf-upgrade.out`). Each output
line is a ready checklist line for the PR body's Ref-scan section; a miss whose target this run
flagged or deleted is marked **Flagged**.

```bash
BRAIN="<brain>"; ACTIONS="<classifier-output>"
( cd "$BRAIN" && grep -rnoE '(pipeline|\.claude/commands|authoring|setup)/[A-Za-z0-9._/-]+\.(md|json)`? +§( [A-Za-z]+|[A-Za-z0-9-]+)' \
    --include='*.md' . 2>/dev/null ) | grep -v '/\.git/' | grep -v 'context/derived/' | sort -u |
while IFS= read -r hit; do
  file=${hit%%:*}; rest=${hit#*:}; line=${rest%%:*}; ref=${rest#*:}
  path=$(printf '%s\n' "$ref" | sed -E 's/`? +§.*//')
  sec=$(printf '%s\n' "$ref" | sed -E 's/.*§//')
  case "$sec" in
    " "*) sec=${sec# }; pat="^#+ +$sec";   label="§ $sec" ;;
    *)                  pat="^#+ +$sec\\."; label="§$sec" ;;
  esac
  grep -qE "$pat" "$BRAIN/$path" 2>/dev/null && continue
  if awk -F'\t' -v p="$path" '($1 ~ /^FLAG-/ || $1 == "SUPERSEDED-FLAG" || $1 == "DELETE-SUPERSEDED") && $2 == p { f = 1 }
                              END { exit !f }' "$ACTIONS" 2>/dev/null
  then echo "- [ ] **Flagged** ${file#./}:$line → \`$path\` $label"
  else echo "- [ ] ${file#./}:$line → \`$path\` $label: no such section"
  fi
done
```

## 5a. Regenerate the map when the generator changed

If this run emitted a new `.brainforge/gen-manifest.sh` (`OVERWRITE` or `ADD` on that path), run
it **from inside the brain** and include the result in the PR:

```bash
( cd "<brain>" && bash .brainforge/gen-manifest.sh )
```

The `cd` is load-bearing: the generator resolves its own repo with `git rev-parse --show-toplevel`,
so running it by path from the Brainforge checkout would regenerate the wrong repo's manifest.

The manifest is generated, never authored, and its schema travels with the generator — a brain
that takes a new script but keeps yesterday's map sits on a manifest the current reader cannot
fully check (a pre-schema-3 map, for instance, cannot answer whether it is stale). The generator
is deterministic and writes nothing but `.brainforge/brain-manifest.json`, so this stays inside
the zero-judgment-in-the-write-path rule.

If the generator came back `FLAG-MODIFIED`, do **not** run it. Say so in the PR body and let the
human reconcile the local change first.

## 6. Land as a PR (golden rule #4) — never a direct write

All writes happen on a branch: `git -C "<brain>" checkout -b upgrade/runtime-<V>` **before**
`--apply`. Stage only the emitted paths + the manifest — **never a blanket `git add -A`** — so a
brain's untracked local files (e.g. Claude Code's per-user `.claude/settings.local.json`) never
ride into the PR. Stage every `DELETE-SUPERSEDED` path too — `git add -- <path>` records a
deletion. A `runtime.remove` path can sit outside every bump glob, so it is not an emitted path:
miss it and the deletion stays in the working tree, the PR never carries it, a fresh checkout
after merge resurrects the file, and the next upgrade flags it again forever. Commit, push, open
the PR with this body shape:

```markdown
## Runtime upgrade → v<V>
Emitted from Brainforge `<emitted-from SHA>`.

### Overwritten (clean) / Added / Adopted (byte-match)
- <file> — <action>

### Deleted (superseded)
- <file> — deleted, staged in this PR

### ⚠️ Flagged — human reconciliation needed in this PR
- [ ] <file> — <flag reason>; shipped version: `scaffold/<file>` @ <SHA>; upstream delta: <UPSTREAM-CHANGED since <sha> + diff | NO-UPSTREAM-CHANGE | BASE-UNKNOWN>  (§3)
- [x] <file> — reconciled; re-baselined to v<V>   (§3 Re-baseline, only while it differs from shipped)

### ⚠️ Refused — `runtime.remove` names a brain-owned path
- [ ] <file> — `SUPERSEDED-REFUSED`; not deleted, fix the `remove` list in `plugin.json`

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
  or any `once` path — the script writes only under bump globs plus the manifest, and its one
  action that reaches outside them, deleting a `runtime.remove` path, refuses every path on that
  list (`SUPERSEDED-REFUSED`). Nothing else may either.
- Never overwrite a file whose hash differs from its manifest baseline, and never touch a
  consumer-added file — flag, don't clobber.
- Never merge content (no LLM-mediated three-way merges) — byte-exact set logic only; humans
  reconcile flags in the PR.
- Never resurrect a consumer-deleted file.
- Never land except via the PR. Never auto-merge it.
