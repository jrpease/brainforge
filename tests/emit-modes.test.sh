#!/usr/bin/env bash
# Emit must preserve the file mode — a 100755 script may not land as 100644 (F10).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

awk '/^```python$/,/^```$/' "$ROOT/commands/upgrade.md" | sed '1d;$d' > "$TMP/bf-upgrade.py"
BF="$TMP/bf"; BR="$TMP/brain"
mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.brainforge" "$BR"
cat > "$BF/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fx", "version": "0.0.1",
  "runtime": { "bump": [".brainforge/**"], "remove": [], "once": [] } }
EOF
printf '#!/usr/bin/env bash\necho hi\n' > "$BF/scaffold/.brainforge/gen-manifest.sh"
chmod 755 "$BF/scaffold/.brainforge/gen-manifest.sh"
printf 'the runtime notes\n' > "$BF/scaffold/.brainforge/README.md"
chmod 644 "$BF/scaffold/.brainforge/README.md"

python3 "$TMP/bf-upgrade.py" "$BF" "$BR" "Acme" --apply > "$TMP/o.txt" 2>&1 || { cat "$TMP/o.txt"; fail "apply failed"; }
[ -f "$BR/.brainforge/gen-manifest.sh" ] || fail "file not emitted"
[ -x "$BR/.brainforge/gen-manifest.sh" ] || fail "emitted gen-manifest.sh is not executable (F10)"
# the other half of "preserve": a 644 source may not land executable either, or the fix is
# just a blanket chmod and every emitted doc becomes a script
[ -f "$BR/.brainforge/README.md" ] || fail "non-executable fixture not emitted"
if [ -x "$BR/.brainforge/README.md" ]; then fail "emitted README.md is executable; emit does not preserve the mode, it grants one"; fi
echo "PASS emit-modes"
