#!/usr/bin/env bash
# sync-contract.sh — will a sync write where the brain said, and leave routing alone?
#
# Every sources.json entry declares `into:`, and for a long time no adapter read it: each one
# hardcoded its own folder and stamped its own `kinds:`. A brain that moved a source's docs to a
# new domain and repointed `into:` had them written back to the old folder on the next sync, with
# the old kinds, and routing silently regressed. The playbooks now say "honour into:, never write
# kinds:". This is the check that fails instead of asking nicely.
#
# Checks, all deterministic (no LLM, no network):
#   1. every enabled source entry in sources.json has an `into:` folder under
#      <contextRoot>/derived/, ending in `/` — no fallback folder exists, so a missing one means
#      that source must not sync. A disabled entry is skipped; enabling it re-runs this check.
#   2. no adapter playbook (pipeline/adapters/*.md, pipeline/examples/*.md) hardcodes a
#      <contextRoot>/derived/<folder> path, outside a `"into":` line in an entry-shape example
#   3. no adapter playbook writes a `kinds:` value (flow list, block list, or bare) — kinds belong
#      to the destination domain
#   4. every adapter playbook names the `into:` field — one that never does cannot be honouring it
#
# contextRoot resolves as gen-manifest.sh does: BRAIN_CONTEXT_DIR, else the manifest's
# contextRoot, else `context`.
#
# USAGE
#   sync-contract.sh            full report   (run by /sync and sync-all before any gate)
#
# EXIT
#   1  a violation, or the check could not run (no python3, unreadable sources.json). Fail
#      closed: a check that cannot run must not read as a pass.
#   0  clean.
set -u

case "${1:-}" in -h|--help) sed -n '2,27p' "$0"; exit 0 ;; esac

root_dir=$(git rev-parse --show-toplevel 2>/dev/null) || root_dir="$PWD"
cd "$root_dir" || { echo "✗ sync-contract: cannot enter $root_dir"; exit 1; }

if ! command -v python3 > /dev/null 2>&1; then
  echo "✗ sync-contract: python3 not found, so into: could not be checked. Do not sync until it can."
  exit 1
fi

python3 - <<'PY'
import glob, json, os, re, sys

bad = []

root = os.environ.get("BRAIN_CONTEXT_DIR", "")
if not root:
    try:
        with open(".brainforge/brain-manifest.json") as f:
            root = json.load(f).get("contextRoot", "") or ""
    except Exception:
        root = ""
root = (root or "context").strip("/")
derived = root + "/derived/"

# 1. sources.json entries
try:
    with open("sources.json") as f:
        sources = json.load(f)
except FileNotFoundError:
    print("✗ sync-contract: no sources.json at the brain root")
    sys.exit(1)
except Exception as e:
    print(f"✗ sync-contract: sources.json does not parse ({e})")
    sys.exit(1)

nentries = 0
for stype, entries in sources.items():
    if stype.startswith("$") or not isinstance(entries, list):
        continue
    for i, e in enumerate(entries):
        if isinstance(e, dict) and e.get("enabled") is False:
            continue
        nentries += 1
        name = f"{stype}[{e.get('id', i) if isinstance(e, dict) else i}]"
        into = e.get("into") if isinstance(e, dict) else None
        if not isinstance(into, str) or not into.strip():
            bad.append(f"✗ sources.json {name}: no into: — this source will not sync until it names its destination")
            continue
        parts = into.split("/")
        if (not into.endswith("/")) or (not into.startswith(derived)) or into == derived \
                or ".." in parts or "" in parts[:-1]:
            bad.append(f"✗ sources.json {name}: into: {into!r} is not a folder under {derived} ending in /")

# 2-4. adapter playbooks
hard = re.compile(re.escape(derived) + r"[A-Za-z0-9_.-]")
stamp = re.compile(r"\bkinds:[ \t]*($|\[|[A-Za-z\"'-])")  # `kinds:` in backticks is prose, not a value
into_word = re.compile(r"`into:?`|\binto:")  # the field, not the English word
playbooks = sorted(glob.glob("pipeline/adapters/*.md") + glob.glob("pipeline/examples/*.md"))
for p in playbooks:
    with open(p, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if not any(into_word.search(l) for l in lines):
        bad.append(f"✗ {p}: never mentions into: — it cannot be writing to the entry's destination")
    for n, l in enumerate(lines, 1):
        if hard.search(l) and '"into":' not in l:
            bad.append(f"✗ {p}:{n}: hardcoded destination — write to the entry's into:, not a fixed folder")
        if stamp.search(l):
            bad.append(f"✗ {p}:{n}: writes kinds: — kinds belong to the destination domain's _index.md")

if bad:
    print("\n".join(bad))
    print(f"\n{len(bad)} sync-contract violation(s). Nothing syncs until these are fixed (pipeline/README.md § Where a sync writes).")
    sys.exit(1)
print(f"✓ sync contract holds: {nentries} source entr{'y' if nentries == 1 else 'ies'} name an into: under {derived}, {len(playbooks)} playbook(s) hardcode no destination and write no kinds.")
PY
