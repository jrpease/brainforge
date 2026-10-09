#!/usr/bin/env bash
# /upgrade §3 KEEP-LOCAL (spec 2026-10-07 D3): an owner-edited bump file that upstream has not
# changed since its baseline (B != M, S == M) is kept as-is and listed, never re-flagged. Before
# this row, an owner-edited .claude/settings.json flagged FLAG-MODIFIED on every upgrade forever.
# Runs the python fence and the re-baseline block exactly as upgrade.md ships them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
G() { git -c user.email=fx@fx -c user.name=fx "$@"; }
emitsha() { printf 'sha256:%s' "$(sed 's/{{ORG}}/Acme/g' "$1" | shasum -a 256 | cut -d' ' -f1)"; }
shaf() { printf 'sha256:%s' "$(shasum -a 256 "$1" | cut -d' ' -f1)"; }
base() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"].get(sys.argv[2]))' "$BR/.brainforge/runtime-manifest.json" "$1"; }

UP="$ROOT/commands/upgrade.md"
awk '/^```python$/,/^```$/' "$UP" | sed '1d;$d' > "$TMP/bf-upgrade.py"
grep -q 'KEEP-LOCAL' "$TMP/bf-upgrade.py" || fail "the extracted python fence has no KEEP-LOCAL row"
awk '/^### Re-baseline /{s=1} s && /^```bash$/ {b=1; next} s && b && /^```$/ {exit} s && b {print}' \
  "$UP" | sed '1s|.*|BF="$1"; BRAIN="$2"; ORG="$3"; F="$4"|' > "$TMP/rebaseline.sh"
grep -q 'REBASELINED' "$TMP/rebaseline.sh" || fail "could not extract the re-baseline block from upgrade.md §3"

BF="$TMP/bf"; BR="$TMP/brain"; SET=.claude/settings.json; SYNC=.claude/commands/sync.md
mkdir -p "$BF/.claude-plugin" "$BF/scaffold/.claude/commands" "$BR/.claude/commands"
release() { # release <version> <settings body> <sync body>: commit a version, keep origin level
  printf '{ "name": "fx", "version": "%s",\n  "runtime": { "bump": [".claude/settings.json", ".claude/commands/**"], "remove": [], "once": [] } }\n' "$1" \
    > "$BF/.claude-plugin/plugin.json"
  printf '%s\n' "$2" > "$BF/scaffold/$SET"
  printf '%s\n' "$3" > "$BF/scaffold/$SYNC"
  git -C "$BF" add -A; G -C "$BF" commit -qm "v$1"
  git -C "$BF" push -q origin HEAD 2> /dev/null || true
}
upgrade() { python3 "$TMP/bf-upgrade.py" "$BF" "$BR" "Acme" "$@"; }
snap() { (cd "$BR" && find . -type f ! -path './.git/*' -exec shasum -a 256 {} + | sort); }

git -C "$BF" init -q; release 0.0.1 '{"hooks":"four inline"}' 'sync v1 for {{ORG}}'
git clone -q --bare "$BF" "$BF.origin"; git -C "$BF" remote add origin "$BF.origin"
git -C "$BF" fetch -q origin; git -C "$BF" remote set-head origin -a > /dev/null

# birth at 0.0.1, then the owner adds a permission to settings.json
printf '{"hooks":"four inline"}\n' > "$BR/$SET"; printf 'sync v1 for Acme\n' > "$BR/$SYNC"
upgrade --apply > /dev/null
printf '{"hooks":"four inline","permissions":"ours"}\n' > "$BR/$SET"

# --- 0.0.2: settings.json changed upstream -> FLAG-MODIFIED; stock sync.md -> OVERWRITE ---
release 0.0.2 '{"hooks":"one script line"}' 'sync v2 for {{ORG}}'
upgrade --apply > "$TMP/u2.txt"
grep -qE "^FLAG-MODIFIED	$SET$" "$TMP/u2.txt" || fail "0.0.2: owner-edited, changed upstream: expected FLAG-MODIFIED (got: $(cat "$TMP/u2.txt"))"
grep -qE "^OVERWRITE	$SYNC$" "$TMP/u2.txt"    || fail "0.0.2: stock file: expected OVERWRITE (got: $(cat "$TMP/u2.txt"))"
grep -q 'KEEP-LOCAL' "$TMP/u2.txt"              && fail "0.0.2: nothing is KEEP-LOCAL while upstream changed it (got: $(cat "$TMP/u2.txt"))"
grep -q '"permissions":"ours"' "$BR/$SET"       || fail "0.0.2: owner edit lost"

# owner reconciles by hand (takes the new hook line, keeps the permission), then re-baselines
printf '{"hooks":"one script line","permissions":"ours"}\n' > "$BR/$SET"
out=$(bash "$TMP/rebaseline.sh" "$BF" "$BR" Acme "$SET") || fail "re-baseline failed: $out"
echo "$out" | grep -qE "^REBASELINED	$SET	0\.0\.2$" || fail "expected REBASELINED (got: $out)"

# --- 0.0.3: settings.json unchanged upstream, sync.md changed -> KEEP-LOCAL, nothing written ---
release 0.0.3 '{"hooks":"one script line"}' 'sync v3 for {{ORG}}'
KEPT=$(base "$SET"); BEFORE=$(shaf "$BR/$SET")
upgrade > "$TMP/dry3.txt"
grep -qE "^KEEP-LOCAL	$SET$" "$TMP/dry3.txt"   || fail "0.0.3 dry run: expected KEEP-LOCAL (got: $(cat "$TMP/dry3.txt"))"
grep -qE "^FLAG-" "$TMP/dry3.txt"               && fail "0.0.3 dry run: nothing should flag (got: $(cat "$TMP/dry3.txt"))"
upgrade --apply > "$TMP/u3.txt"
grep -qE "^KEEP-LOCAL	$SET$" "$TMP/u3.txt"     || fail "0.0.3 apply: expected KEEP-LOCAL (got: $(cat "$TMP/u3.txt"))"
grep -qE "^OVERWRITE	$SYNC$" "$TMP/u3.txt"    || fail "0.0.3 apply: changed stock file: expected OVERWRITE (got: $(cat "$TMP/u3.txt"))"
[ "$(shaf "$BR/$SET")" = "$BEFORE" ]            || fail "0.0.3: KEEP-LOCAL wrote to the file"
[ "$(base "$SET")" = "$KEPT" ]                  || fail "0.0.3: KEEP-LOCAL must keep its baseline"
[ "$(base "$SET")" = "$(emitsha "$BF/scaffold/$SET")" ] || fail "0.0.3: the kept baseline must equal the shipped hash"
[ "$(base "$SET")" != "$(shaf "$BR/$SET")" ]    || fail "0.0.3: a baseline must never equal the owner's bytes"
grep -q 'sync v3 for Acme' "$BR/$SYNC"          || fail "0.0.3: OVERWRITE did not emit"

# --- same-version re-run: UP-TO-DATE, and the kept baseline causes no UNBUMPED-CHANGE ---
S1=$(snap)
out=$(upgrade) || fail "same-version re-run failed: $out"
[ "$out" = "$(printf 'UP-TO-DATE\t0.0.3')" ]    || fail "same-version re-run: expected exactly UP-TO-DATE 0.0.3 (got: $out)"
[ "$(snap)" = "$S1" ]                           || fail "same-version re-run wrote to the brain"

# --- 0.0.4: upstream edits settings.json again -> flags again (KEEP-LOCAL is not a permanent pass) ---
release 0.0.4 '{"hooks":"one script line v2"}' 'sync v3 for {{ORG}}'
out=$(upgrade)
echo "$out" | grep -qE "^FLAG-MODIFIED	$SET$" || fail "0.0.4: upstream changed a kept file: expected FLAG-MODIFIED (got: $out)"

# --- the PR body carries the KEEP-LOCAL list and the settings.json migration line ---
grep -q '^### Yours, nothing upstream to bring in$' "$UP"    || fail "PR body has no KEEP-LOCAL section"
grep -qE '^- <file> — `KEEP-LOCAL`' "$UP"                     || fail "PR body KEEP-LOCAL section lists no file line"
grep -qE '^- \[ \] \.claude/settings\.json — .*session-start\.sh' "$UP" || fail "PR body has no settings.json migration line"
grep -qE '^\| `KEEP-LOCAL` \|' "$UP"                         || fail "action table has no KEEP-LOCAL row"

echo "PASS upgrade-keep-local"
