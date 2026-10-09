#!/usr/bin/env bash
# runtime.remove must be consumed on BOTH the steady-state and the adoption path (F4).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# same extraction commands/forge.md §3 uses — this also guards that contract
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

mkfixture() {                      # $1 = dir, $2 = with-manifest (yes/no)
  local BF="$1/bf" BR="$1/brain"
  mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands"
  cat > "$BF/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fx", "version": "0.0.2",
  "runtime": { "bump": [".claude/commands/**"], "remove": [".claude/commands/walk.md"], "once": [] } }
EOF
  printf 'shipped forge\n' > "$BF/scaffold/.claude/commands/forge.md"
  printf 'shipped forge\n' > "$BR/.claude/commands/forge.md"
  printf 'legacy walk command\n' > "$BR/.claude/commands/walk.md"
  gitify "$BF"
  if [ "$2" = yes ]; then
    mkdir -p "$BR/.brainforge"
    python3 - "$BR" <<'PY'
import hashlib, json, pathlib, sys
BR = pathlib.Path(sys.argv[1])
def sha(p): return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()
files = {".claude/commands/forge.md": sha(BR/".claude/commands/forge.md"),
         ".claude/commands/walk.md":  sha(BR/".claude/commands/walk.md")}
(BR/".brainforge"/"runtime-manifest.json").write_text(
    json.dumps({"runtime-version": "0.0.1", "emitted-from": "x", "files": files}, indent=2) + "\n")
PY
  fi
}

# --- case A: steady state, walk.md unmodified since emit -> delete ---
mkdir -p "$TMP/a"; mkfixture "$TMP/a" yes
python3 "$TMP/bf-upgrade.py" "$TMP/a/bf" "$TMP/a/brain" "Acme" > "$TMP/a.txt" 2>&1 || true
echo "--- case A (with manifest) ---"; cat "$TMP/a.txt"
grep -qE '^DELETE-SUPERSEDED	\.claude/commands/walk\.md$' "$TMP/a.txt" \
  || fail "steady state: expected DELETE-SUPERSEDED for walk.md"

# --- case B: adoption pass, no manifest -> flag loudly, never silent ---
mkdir -p "$TMP/b"; mkfixture "$TMP/b" no
python3 "$TMP/bf-upgrade.py" "$TMP/b/bf" "$TMP/b/brain" "Acme" > "$TMP/b.txt" 2>&1 || true
echo "--- case B (adoption pass) ---"; cat "$TMP/b.txt"
grep -qE '^SUPERSEDED-FLAG	\.claude/commands/walk\.md$' "$TMP/b.txt" \
  || fail "adoption pass: expected SUPERSEDED-FLAG for walk.md"

mkfixture_outofglob() {            # $1 = dir -- remove path outside every bump glob
  local BF="$1/bf" BR="$1/brain"
  mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands" "$BR/docs" "$BR/.brainforge"
  cat > "$BF/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fx", "version": "0.0.2",
  "runtime": { "bump": [".claude/commands/**"], "remove": ["docs/legacy-notes.md"], "once": [] } }
EOF
  printf 'shipped forge\n' > "$BF/scaffold/.claude/commands/forge.md"
  printf 'shipped forge\n' > "$BR/.claude/commands/forge.md"
  printf 'legacy notes, unmodified since emit\n' > "$BR/docs/legacy-notes.md"
  gitify "$BF"
  python3 - "$BR" <<'PY'
import hashlib, json, pathlib, sys
BR = pathlib.Path(sys.argv[1])
def sha(p): return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()
files = {".claude/commands/forge.md": sha(BR/".claude/commands/forge.md"),
         "docs/legacy-notes.md":      sha(BR/"docs/legacy-notes.md")}
(BR/".brainforge"/"runtime-manifest.json").write_text(
    json.dumps({"runtime-version": "0.0.1", "emitted-from": "x", "files": files}, indent=2) + "\n")
PY
}

# --- case C: steady state, remove path OUTSIDE every bump glob, unmodified since emit -> delete ---
mkdir -p "$TMP/c"; mkfixture_outofglob "$TMP/c"
python3 "$TMP/bf-upgrade.py" "$TMP/c/bf" "$TMP/c/brain" "Acme" > "$TMP/c.txt" 2>&1 || true
echo "--- case C (out-of-glob remove path) ---"; cat "$TMP/c.txt"
grep -qE '^DELETE-SUPERSEDED	docs/legacy-notes\.md$' "$TMP/c.txt" \
  || fail "out-of-glob: expected DELETE-SUPERSEDED for docs/legacy-notes.md"

mkfixture_brainowned() {           # $1 = dir -- remove path that is a `once` path
  local BF="$1/bf" BR="$1/brain"
  mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands" "$BR/.brainforge"
  cat > "$BF/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fx", "version": "0.0.2",
  "runtime": { "bump": [".claude/commands/**"], "remove": ["sources.json"],
               "once": ["sources.json"] } }
EOF
  printf 'shipped forge\n' > "$BF/scaffold/.claude/commands/forge.md"
  printf 'shipped forge\n' > "$BR/.claude/commands/forge.md"
  printf '{ "figma": [] }\n' > "$BR/sources.json"
  gitify "$BF"
  python3 - "$BR" <<'PY'
import hashlib, json, pathlib, sys
BR = pathlib.Path(sys.argv[1])
def sha(p): return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()
files = {".claude/commands/forge.md": sha(BR/".claude/commands/forge.md"),
         "sources.json":              sha(BR/"sources.json")}
(BR/".brainforge"/"runtime-manifest.json").write_text(
    json.dumps({"runtime-version": "0.0.1", "emitted-from": "x", "files": files}, indent=2) + "\n")
PY
}

# --- case D: remove names a `once` path whose hash matches -> refuse, never delete ---
mkdir -p "$TMP/d"; mkfixture_brainowned "$TMP/d"
python3 "$TMP/bf-upgrade.py" "$TMP/d/bf" "$TMP/d/brain" "Acme" --apply > "$TMP/d.txt" 2>&1 || true
echo "--- case D (once path in runtime.remove) ---"; cat "$TMP/d.txt"
grep -qE '^SUPERSEDED-REFUSED	sources\.json$' "$TMP/d.txt" \
  || fail "once path: expected SUPERSEDED-REFUSED for sources.json"
if grep -qE '^DELETE-SUPERSEDED	sources\.json$' "$TMP/d.txt"; then
  fail "once path: sources.json was classified for deletion"
fi
[ -f "$TMP/d/brain/sources.json" ] || fail "once path: sources.json was deleted on --apply"
if grep -q '"sources.json"' "$TMP/d/brain/.brainforge/runtime-manifest.json"; then
  fail "once path: refused sources.json earned a manifest entry"
fi

echo "PASS upgrade-remove"
