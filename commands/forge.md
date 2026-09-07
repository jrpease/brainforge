---
description: Bootstrap a brain in the current directory from this plugin's scaffold, then hand off to the brain-resident /forge wizard.
---

# /forge — bootstrap a brain (builder-side)

Run **in the directory that should become a brain** — either an empty repo or an existing one with
no brain in it yet. This is the plugin-resident half of `/forge`: it exists so a fresh install has
*something* to answer `/forge` with. It does exactly one job — emit the scaffold and hand off — and
never duplicates the brain-resident wizard (`setup/README.md` + `.claude/commands/forge.md`, both
emitted below) that actually drives the domain-by-domain setup loop.

**Arguments:** none. The org name is confirmed interactively (guard 4).

## 0. Locate the source

`SRC_ROOT` is the directory containing both `.claude-plugin/` and `scaffold/`:

- Running as an installed plugin: `SRC_ROOT = ${CLAUDE_PLUGIN_ROOT}`.
- Running from a Brainforge checkout (no `CLAUDE_PLUGIN_ROOT` set): `SRC_ROOT` is the checkout
  root — guard it the same way `upgrade.md` guards its own checkout: `SRC_ROOT/.claude-plugin/plugin.json`
  and `SRC_ROOT/scaffold/` must both exist.

## 1. Guards — all before any write

1. **Already a brain?** If `sources.json` exists in the current directory, this is not a fresh
   install — it's a scaffolded brain. Say so, tell the user to run the **brain-resident** `/forge`
   (it drives the whole setup loop — this command has nothing further to do here), and **STOP**.
   No writes.
2. **Git repo?** `git rev-parse --git-dir` must succeed in the cwd. If it doesn't, **ask** the user
   whether to `git init` — never assume. If they decline, stop.
3. **Collision check.** None of the scaffold's top-level entries may already exist in the cwd:
   `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `sources.json`, `.sync-state.json`, `context/`,
   `pipeline/`, `authoring/`, `setup/`, `templates/`, `.claude/`, `.brainforge/`, `.gitignore`,
   `.gitattributes`, `.env.example`. If any exist, list them and **STOP** — never overwrite. (A
   partial or drifted brain is `/upgrade`'s job, not this command's — this command only ever
   bootstraps from nothing.)
4. **Confirm `{{ORG}}`.** Ask the user for the org name before emitting anything — it lands in the
   emitted `README.md` H1 (`# <ORG> — Shared Context`) and in the birth manifest's hashes.
   Mirrors `upgrade.md` guard 4's confirm-before-emitting rule: a wrong value makes every future
   hash comparison wrong.

## 2. Emit = copy + template — never a raw copy

Same rule as `upgrade.md` §2: `emitted(f)` is the scaffold file with every `{{ORG}}` byte-sequence
replaced by the confirmed org name. Deterministic, stdlib-only, no LLM judgment in the write path:

```bash
python3 - "$SRC_ROOT" "$(pwd)" "<ORG>" <<'PYEOF'
import pathlib, sys
SRC, DST, ORG = pathlib.Path(sys.argv[1]) / "scaffold", pathlib.Path(sys.argv[2]), sys.argv[3].encode()
for src in sorted(SRC.rglob("*")):
    if not src.is_file():
        continue
    rel = src.relative_to(SRC)
    dst = DST / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(src.read_bytes().replace(b"{{ORG}}", ORG))
    dst.chmod(src.stat().st_mode)
print("EMITTED", sum(1 for p in SRC.rglob("*") if p.is_file()), "files")
PYEOF
```

Replace `<ORG>` with the value confirmed in guard 4 (quoted — org names may contain spaces).

## 3. Birth manifest — the script is the contract

Extract the same `bf-upgrade.py` `upgrade.md` uses (never hand-maintain a second copy):

```bash
awk '/^```python$/,/^```$/' "$SRC_ROOT/commands/upgrade.md" | sed '1d;$d' > bf-upgrade.py
python3 bf-upgrade.py "$SRC_ROOT" "$(pwd)" "<ORG>" --apply
```

This is `upgrade.md` §3's documented **scaffold-time bootstrap**: no manifest exists yet, so it's
an adoption pass over a freshly emitted tree — every bump file byte-matches what was just emitted,
so every line is `ADOPT-CLEAN` (plus any `ADD` for files the classifier still needs to place),
followed by one `APPLIED\tmanifest -> <V> (<n> files)` line. That call writes the birth
`.brainforge/runtime-manifest.json`. Do not write that file by hand — if the run prints anything
other than `ADOPT-CLEAN`/`ADD` lines + `APPLIED`, stop and reconcile before committing (it means
the scaffold and the classifier disagree, which should not happen on a fresh emit).

Delete the scratch `bf-upgrade.py` after a successful apply — it's not part of the emitted set.

## 4. Initial commit

Read `V` from `SRC_ROOT/.claude-plugin/plugin.json`. On a fresh repo, `git add -A` is acceptable
(say so explicitly — there is nothing pre-existing to accidentally sweep in, unlike `/upgrade`
landing into a populated brain). Commit:

```
chore(brain): scaffold from brainforge v<V>
```

## 5. Hand off

Tell the user, in one sentence: the brain now carries its own `/forge`
(`.claude/commands/forge.md`); restart the session so it loads, then run `/forge` again — that
starts the real depth-first setup wizard. Point at `setup/README.md` for what that wizard does. Do
not restate its loop here.

## Never

- Never overwrite a file that already exists in the cwd — a collision means stop and report, not
  merge or clobber.
- Never emit into a non-git directory without the user's explicit consent to `git init`.
- Never skip or infer the `{{ORG}}` confirmation — always ask.
- Never write `.brainforge/runtime-manifest.json` by hand — `bf-upgrade.py --apply` is the only
  writer, here and on every future `/upgrade`.
- Never duplicate the brain-resident wizard's domain loop in this command — bootstrap, then defer.
