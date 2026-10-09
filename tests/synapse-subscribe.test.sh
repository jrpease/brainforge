#!/usr/bin/env bash
# Test the bf-subscribe.py script embedded in synapse/commands/subscribe.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# extract the first python fence (same convention the command itself uses)
awk '/^```python$/{f=1;next} /^```$/{if(f)exit} f' "$ROOT/synapse/commands/subscribe.md" > "$TMP/bf-subscribe.py"
[ -s "$TMP/bf-subscribe.py" ] || fail "could not extract python fence"

S="$TMP/settings.json"

# local fixture brain repo so the access probe can succeed
BRAIN="$TMP/brain"; git init -q "$BRAIN"; git -C "$BRAIN" commit -q --allow-empty -m x

# 1. fresh file: created, env + dirs set, valid JSON
out=$(python3 "$TMP/bf-subscribe.py" "$BRAIN" --settings "$S")
python3 -m json.tool "$S" > /dev/null                     || fail "fresh settings not valid JSON"
grep -q "\"SYNAPSE_BRAINS\": \"$BRAIN\"" "$S"             || fail "brain not recorded"
grep -q '"~/.synapse"' "$S"                                || fail "additionalDirectories missing ~/.synapse"
echo "$out" | grep -q "subscribed ✓"                       || fail "no success line"
echo "$out" | grep -q "⚠ access" && fail "access probe should pass on local fixture"

# 2. existing settings preserved
python3 - "$S" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1])); s["model"] = "opus"; s["env"]["OTHER"] = "keep"
json.dump(s, open(sys.argv[1], "w"), indent=2)
EOF
python3 "$TMP/bf-subscribe.py" "$BRAIN" --settings "$S" > /dev/null
grep -q '"model": "opus"' "$S"                             || fail "existing top-level key clobbered"
grep -q '"OTHER": "keep"' "$S"                             || fail "existing env key clobbered"

# 3. duplicate subscribe: no dup, says already subscribed (trailing slash normalized)
out=$(python3 "$TMP/bf-subscribe.py" "$BRAIN/" --settings "$S")
echo "$out" | grep -q "already subscribed"                 || fail "duplicate not detected"
[ "$(grep -o "$BRAIN" "$S" | wc -l | tr -d ' ')" -le 2 ]   || fail "brain recorded twice"

# 4. second brain appends comma-separated
BRAIN2="$TMP/brain2"; git init -q "$BRAIN2"; git -C "$BRAIN2" commit -q --allow-empty -m x
python3 "$TMP/bf-subscribe.py" "$BRAIN2" --settings "$S" > /dev/null
grep -q "\"SYNAPSE_BRAINS\": \"$BRAIN,$BRAIN2\"" "$S"      || fail "second brain not appended"

# 5. unreachable remote: warns but still subscribes, exit 0
out=$(python3 "$TMP/bf-subscribe.py" "$TMP/nope" --settings "$S") || fail "unreachable brain must not hard-fail"
echo "$out" | grep -q "⚠ access"                           || fail "no access warning for unreachable brain"
grep -q "nope" "$S"                                        || fail "unreachable brain not recorded"

# 6. corrupt settings: refuses, exits nonzero, file untouched
echo '{broken' > "$S"
if python3 "$TMP/bf-subscribe.py" "$BRAIN" --settings "$S" > /dev/null 2>&1; then
  fail "corrupt settings must be refused"
fi
[ "$(cat "$S")" = '{broken' ]                              || fail "corrupt settings file was modified"

# CLAUDE_CONFIG_DIR: Claude reads settings from there when set, so the subscription must land there
CFG="$TMP/cfgdir"; mkdir -p "$CFG"
CLAUDE_CONFIG_DIR="$CFG" HOME="$TMP/home" python3 "$TMP/bf-subscribe.py" "$BRAIN" > /dev/null
grep -q SYNAPSE_BRAINS "$CFG/settings.json" 2>/dev/null   || fail "CLAUDE_CONFIG_DIR ignored: subscription not written to \$CLAUDE_CONFIG_DIR/settings.json"
[ ! -e "$TMP/home/.claude/settings.json" ]                || fail "wrote ~/.claude/settings.json despite CLAUDE_CONFIG_DIR"

echo "PASS synapse-subscribe"
