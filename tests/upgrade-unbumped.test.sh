#!/usr/bin/env bash
# A bump-path change shipped without a version bump must not hide behind UP-TO-DATE (pub #25).
# The version gate short-circuits only when every shipped bump file matches its manifest baseline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# same extraction commands/forge.md §3 uses
awk '/^```python$/,/^```$/' "$ROOT/commands/upgrade.md" | sed '1d;$d' > "$TMP/bf-upgrade.py"
[ -s "$TMP/bf-upgrade.py" ] || fail "could not extract the upgrade fence"

# gitify <bf-dir>: make the fixture checkout a git repo level with its own origin, so the §1
# checkout-freshness guard can prove it current (a non-git copy with no repository refuses)
gitify() {
  git -C "$1" init -q; git -C "$1" add -A
  git -C "$1" -c user.email=fx@fx -c user.name=fx commit -qm fx
  git clone -q --bare "$1" "$1.origin"; git -C "$1" remote add origin "$1.origin"
  git -C "$1" fetch -q origin; git -C "$1" remote set-head origin -a > /dev/null
}
recommit() { git -C "$1" add -A; git -C "$1" -c user.email=fx@fx -c user.name=fx commit -qm fx; }

mkfixture() {                      # $1 = dir -- a brain emitted at the checkout's version
  local BF="$1/bf" BR="$1/brain"
  mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands"
  cat > "$BF/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fx", "version": "0.0.2",
  "runtime": { "bump": [".claude/commands/**"], "remove": [], "once": [] } }
EOF
  printf 'shipped forge for {{ORG}}\n' > "$BF/scaffold/.claude/commands/forge.md"
  printf 'shipped sync\n' > "$BF/scaffold/.claude/commands/sync.md"
  printf 'shipped forge for Acme\n' > "$BR/.claude/commands/forge.md"
  printf 'shipped sync\n' > "$BR/.claude/commands/sync.md"
  gitify "$BF"
  # birth manifest at 0.0.2, written by the script itself (adoption pass, as /forge does)
  python3 "$TMP/bf-upgrade.py" "$BF" "$BR" "Acme" --apply > "$1/birth.txt" 2>&1 \
    || { cat "$1/birth.txt"; fail "could not write the birth manifest"; }
  grep -q '"runtime-version": "0.0.2"' "$BR/.brainforge/runtime-manifest.json" \
    || fail "birth manifest is not at 0.0.2"
}

# --- case A: nothing changed -> UP-TO-DATE, nothing else ---
mkdir -p "$TMP/a"; mkfixture "$TMP/a"
python3 "$TMP/bf-upgrade.py" "$TMP/a/bf" "$TMP/a/brain" "Acme" > "$TMP/a.txt" 2>&1 || true
echo "--- case A (unmodified brain, same version) ---"; cat "$TMP/a.txt"
[ "$(cat "$TMP/a.txt")" = "$(printf 'UP-TO-DATE\t0.0.2')" ] \
  || fail "unmodified brain: expected exactly UP-TO-DATE 0.0.2"

# --- case B: a scaffold bump file changed, version not bumped -> UNBUMPED-CHANGE + update ---
mkdir -p "$TMP/b"; mkfixture "$TMP/b"
printf 'shipped sync, fixed without a bump\n' > "$TMP/b/bf/scaffold/.claude/commands/sync.md"
recommit "$TMP/b/bf"
python3 "$TMP/bf-upgrade.py" "$TMP/b/bf" "$TMP/b/brain" "Acme" > "$TMP/b.txt" 2>&1 || true
echo "--- case B (unbumped scaffold change) ---"; cat "$TMP/b.txt"
grep -qE '^UNBUMPED-CHANGE	0\.0\.2	1 file\(s\)$' "$TMP/b.txt" \
  || fail "unbumped change: expected UNBUMPED-CHANGE 0.0.2 1 file(s)"
grep -qE '^OVERWRITE	\.claude/commands/sync\.md$' "$TMP/b.txt" \
  || fail "unbumped change: expected OVERWRITE for the changed sync.md"
if grep -q '^UP-TO-DATE' "$TMP/b.txt"; then fail "unbumped change: still printed UP-TO-DATE"; fi

# --- case C: a tombstoned (consumer-deleted) file is not an unbumped change ---
mkdir -p "$TMP/c"; mkfixture "$TMP/c"
python3 - "$TMP/c/brain" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]) / ".brainforge" / "runtime-manifest.json"
m = json.loads(p.read_text()); m["files"][".claude/commands/sync.md"] = None
p.write_text(json.dumps(m, indent=2) + "\n")
PY
rm "$TMP/c/brain/.claude/commands/sync.md"
python3 "$TMP/bf-upgrade.py" "$TMP/c/bf" "$TMP/c/brain" "Acme" > "$TMP/c.txt" 2>&1 || true
echo "--- case C (tombstone, same version) ---"; cat "$TMP/c.txt"
[ "$(cat "$TMP/c.txt")" = "$(printf 'UP-TO-DATE\t0.0.2')" ] \
  || fail "tombstone: expected exactly UP-TO-DATE 0.0.2"

# --- case D: a bump file deleted upstream, version not bumped -> UNBUMPED-CHANGE + delete (pub #34) ---
mkdir -p "$TMP/d"; mkfixture "$TMP/d"
rm "$TMP/d/bf/scaffold/.claude/commands/sync.md"
recommit "$TMP/d/bf"
python3 "$TMP/bf-upgrade.py" "$TMP/d/bf" "$TMP/d/brain" "Acme" > "$TMP/d.txt" 2>&1 || true
echo "--- case D (bump file deleted upstream, no bump) ---"; cat "$TMP/d.txt"
grep -qE '^UNBUMPED-CHANGE	0\.0\.2	1 file\(s\)$' "$TMP/d.txt" \
  || fail "upstream deletion: expected UNBUMPED-CHANGE 0.0.2 1 file(s)"
grep -qE '^DELETE-SUPERSEDED	\.claude/commands/sync\.md$' "$TMP/d.txt" \
  || fail "upstream deletion: expected DELETE-SUPERSEDED for the removed sync.md"
if grep -q '^UP-TO-DATE' "$TMP/d.txt"; then fail "upstream deletion: still printed UP-TO-DATE"; fi

echo "PASS upgrade-unbumped"
