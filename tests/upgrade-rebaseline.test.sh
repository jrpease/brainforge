#!/usr/bin/env bash
# /upgrade §3 "Upstream delta for a flagged file" and "Re-baseline a reconciled file": a
# FLAG-MODIFIED file reconciled by hand gets its baseline moved to the current shipped hash, ONLY
# while it still differs from shipped, so the next delta starts there. Found for real: three files
# reconciled at 0.7.0 flagged again at 0.10.0 and re-presented changes already brought in.
# Runs both bash blocks exactly as upgrade.md ships them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
G() { git -c user.email=fx@fx -c user.name=fx "$@"; }
emitsha() { printf 'sha256:%s' "$(sed 's/{{ORG}}/Acme/g' "$1" | shasum -a 256 | cut -d' ' -f1)"; }
shaf() { printf 'sha256:%s' "$(shasum -a 256 "$1" | cut -d' ' -f1)"; }
base() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"].get(sys.argv[2]))' "$BR/.brainforge/runtime-manifest.json" "$1"; }

awk '/^```python$/,/^```$/' "$ROOT/commands/upgrade.md" | sed '1d;$d' > "$TMP/bf-upgrade.py"
awk '/^### Re-baseline /{s=1} s && /^```bash$/ {b=1; next} s && b && /^```$/ {exit} s && b {print}' \
  "$ROOT/commands/upgrade.md" | sed '1s|.*|BF="$1"; BRAIN="$2"; ORG="$3"; F="$4"|' > "$TMP/rebaseline.sh"
grep -q 'REBASELINED' "$TMP/rebaseline.sh" || fail "could not extract the re-baseline block from upgrade.md §3"
awk '/^### Upstream delta /{s=1} s && /^```bash$/ {b=1; next} s && b && /^```$/ {exit} s && b {print}' \
  "$ROOT/commands/upgrade.md" | sed '1s|.*|BF="$1"; BRAIN="$2"; ORG="$3"; F="$4"|' > "$TMP/delta.sh"
grep -q 'NO-UPSTREAM-CHANGE' "$TMP/delta.sh" || fail "could not extract the upstream delta block from upgrade.md §3"
delta() { bash "$TMP/delta.sh" "$BF" "$1" Acme "$SYNC"; }

BF="$TMP/bf"; BR="$TMP/brain"; SYNC=.claude/commands/sync.md
mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands"
release() { # release <version> <sync.md body>: commit a Brainforge version and keep origin level
  printf '{ "name": "fx", "version": "%s",\n  "runtime": { "bump": [".claude/commands/**"], "remove": [], "once": [] } }\n' "$1" \
    > "$BF/.claude-plugin/plugin.json"
  printf '%s\n' "$2" > "$BF/scaffold/$SYNC"
  git -C "$BF" add -A; G -C "$BF" commit -qm "v$1"
  git -C "$BF" push -q origin HEAD 2> /dev/null || true
}
upgrade() { python3 "$TMP/bf-upgrade.py" "$BF" "$BR" "Acme" "$@"; }

git -C "$BF" init -q; release 0.0.1 'sync v1 for {{ORG}}'
git clone -q --bare "$BF" "$BF.origin"; git -C "$BF" remote add origin "$BF.origin"
git -C "$BF" fetch -q origin; git -C "$BF" remote set-head origin -a > /dev/null

# birth at 0.0.1, then the brain adds its permanent local lines
printf 'sync v1 for Acme\n' > "$BR/$SYNC"; upgrade --apply > /dev/null
printf 'sync v1 for Acme\nour local step\n' > "$BR/$SYNC"
V1=$(base "$SYNC")

# 0.0.2 changes sync.md upstream -> FLAG-MODIFIED, old baseline kept (by design)
release 0.0.2 'sync v2 for {{ORG}}'
upgrade --apply > "$TMP/u2.txt"
grep -qE "^FLAG-MODIFIED	$SYNC$" "$TMP/u2.txt" || fail "0.0.2: expected FLAG-MODIFIED (got: $(cat "$TMP/u2.txt"))"
[ "$(base "$SYNC")" = "$V1" ]                     || fail "0.0.2: FLAG-MODIFIED must keep the old baseline"
out=$(delta "$BR")
echo "$out" | grep -q '^UPSTREAM-CHANGED'          || fail "0.0.2 delta: expected UPSTREAM-CHANGED (got: $out)"
echo "$out" | grep -q '^+sync v2'                  || fail "0.0.2 delta: must show the upstream edit (got: $out)"

# --- took shipped: a file reconciled to stock is adopted, and stops flagging ---
ST="$TMP/stock"; cp -R "$BR" "$ST"; printf 'sync v2 for Acme\n' > "$ST/$SYNC"
out=$(bash "$TMP/rebaseline.sh" "$BF" "$ST" Acme "$SYNC") || fail "a stock file must be adopted: $out"
echo "$out" | grep -qE "^ADOPTED-STOCK	$SYNC	0\.0\.2$" || fail "expected ADOPTED-STOCK (got: $out)"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][sys.argv[2]])' "$ST/.brainforge/runtime-manifest.json" "$SYNC")" = "$(shaf "$ST/$SYNC")" ] \
  || fail "a stock file's baseline must be its shipped hash"
out=$(python3 "$TMP/bf-upgrade.py" "$BF" "$ST" Acme) || fail "upgrade after adopting a stock file failed: $out"
echo "$out" | grep -q '^UP-TO-DATE'                  || fail "a stock file must stop flagging (got: $out)"

# --- a reconciled collision: no baseline, differs from shipped -> adopted at the shipped hash ---
CO="$TMP/collision"; cp -R "$BR" "$CO"; printf 'sync v2 for Acme\nour local step\n' > "$CO/$SYNC"
python3 -c 'import json,sys; p=sys.argv[1]; m=json.load(open(p)); del m["files"][sys.argv[2]]; open(p,"w").write(json.dumps(m,indent=2)+"\n")' \
  "$CO/.brainforge/runtime-manifest.json" "$SYNC"
out=$(bash "$TMP/rebaseline.sh" "$BF" "$CO" Acme "$SYNC") || fail "a reconciled collision must be adopted: $out"
echo "$out" | grep -qE "^ADOPTED-COLLISION	$SYNC	0\.0\.2$" || fail "expected ADOPTED-COLLISION (got: $out)"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][sys.argv[2]])' "$CO/.brainforge/runtime-manifest.json" "$SYNC")" != "$(shaf "$CO/$SYNC")" ] \
  || fail "an adopted collision's baseline must never equal its bytes"

# --- refusal: a file this checkout does not ship ---
out=$(bash "$TMP/rebaseline.sh" "$BF" "$BR" Acme .claude/commands/nope.md 2>&1) && fail "an unshipped file must refuse"
echo "$out" | grep -q '^REFUSED.*not shipped' || fail "must say not shipped (got: $out)"

# --- the step: reconciled = upstream v2 + the local line, still differs from shipped ---
printf 'sync v2 for Acme\nour local step\n' > "$BR/$SYNC"
cp -R "$BR" "$TMP/not-rebaselined"     # the reported case: reconciled, never re-baselined
out=$(bash "$TMP/rebaseline.sh" "$BF" "$BR" Acme "$SYNC") || fail "re-baseline of a reconciled file failed: $out"
echo "$out" | grep -qE "^REBASELINED	$SYNC	0\.0\.2$" || fail "expected REBASELINED (got: $out)"
[ "$(base "$SYNC")" = "$(emitsha "$BF/scaffold/$SYNC")" ] || fail "baseline must be the shipped hash, as emitted ({{ORG}} substituted)"
[ "$(base "$SYNC")" != "$(shaf "$BR/$SYNC")" ]       || fail "baseline must never equal the on-disk bytes"
out=$(bash "$TMP/rebaseline.sh" "$BF" "$BR" Acme "$SYNC") || fail "re-running must not fail"
echo "$out" | grep -q '^UNCHANGED'                   || fail "re-running must be idempotent (got: $out)"

# --- next version: the local additions survive, and the baseline carried forward is 0.0.2's ---
release 0.0.3 'sync v2 for {{ORG}}'
V2=$(base "$SYNC")
upgrade --apply > "$TMP/u3.txt"
grep -qE "^OVERWRITE	$SYNC$" "$TMP/u3.txt"         && fail "a re-baselined file was overwritten, losing its local additions"
grep -qE "^KEEP-LOCAL	$SYNC$" "$TMP/u3.txt"        || fail "0.0.3, unchanged upstream since the re-baseline: expected KEEP-LOCAL (got: $(cat "$TMP/u3.txt"))"
grep -q 'our local step' "$BR/$SYNC"                 || fail "local additions lost"
[ "$(base "$SYNC")" = "$V2" ]                        || fail "0.0.3 must carry the re-baselined 0.0.2 hash, not the 0.0.1 one"
out=$(delta "$BR")
echo "$out" | grep -q '^NO-UPSTREAM-CHANGE'           || fail "0.0.3 delta, re-baselined: expected NO-UPSTREAM-CHANGE (got: $out)"
out=$(delta "$TMP/not-rebaselined")
echo "$out" | grep -q '^UPSTREAM-CHANGED'             || fail "0.0.3 delta, not re-baselined: must re-present the 0.0.2 change (got: $out)"
out=$(python3 "$TMP/bf-upgrade.py" "$BF" "$CO" Acme --apply)
echo "$out" | grep -qE "^KEEP-LOCAL	$SYNC$"          || fail "0.0.3: an adopted collision unchanged upstream must be KEEP-LOCAL, not collide (got: $out)"
grep -q 'our local step' "$CO/$SYNC"                  || fail "0.0.3: an adopted collision lost its local lines"
out=$(delta "$CO")
echo "$out" | grep -q '^NO-UPSTREAM-CHANGE'           || fail "0.0.3 delta, adopted collision: expected NO-UPSTREAM-CHANGE (got: $out)"

# --- refusal: manifest and checkout at different versions (re-baseline before --apply) ---
release 0.0.4 'sync v4 for {{ORG}}'
out=$(delta "$BR")
echo "$out" | grep -q '^+sync v4'                     || fail "0.0.4 delta: must show the new upstream edit (got: $out)"
echo "$out" | grep -q 'sync v1'                       && fail "0.0.4 delta: must not reach back before the re-baseline (got: $out)"
out=$(bash "$TMP/rebaseline.sh" "$BF" "$BR" Acme "$SYNC" 2>&1) && fail "version mismatch must refuse"
echo "$out" | grep -q '^REFUSED.*--apply this upgrade first' || fail "must say to apply first (got: $out)"

echo "PASS upgrade-rebaseline"
