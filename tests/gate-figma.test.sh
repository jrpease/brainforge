#!/usr/bin/env bash
# Offline test for scaffold/.brainforge/gate-figma.sh: recorded responses via the curl stub,
# PATH holds only the stub dir plus the system dirs, no network, no credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/scaffold/.brainforge/gate-figma.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin/curl"
export PATH="$TMP/bin:/usr/bin:/bin"

# fresh brain + fixture dir per case: new_case <name> -> sets BRAIN and CURL_STUB_DIR
new_case() {
  BRAIN="$TMP/$1"; mkdir -p "$BRAIN"; CURL_STUB_DIR="$TMP/$1-fx"; mkdir -p "$CURL_STUB_DIR"
  cp "$ROOT"/tests/fixtures/gates/figma/*.http "$CURL_STUB_DIR/"; export CURL_STUB_DIR
  echo "FIGMA_TOKEN=fake-token-for-tests" > "$BRAIN/.env"
}
# entry <id> <fileKey> <into> -> JSON object (into may be "")
entry() { printf '{"id":"%s","fileKey":"%s","into":"%s","enabled":true,"extract":["styles"]}' "$1" "$2" "$3"; }
sources() { local IFS=,; printf '{"version":1,"figma":[%s]}' "$*" > "$BRAIN/sources.json"; }
slot() { printf '"%s":{"version":"%s","lastModified":"2026-01-01T00:00:00Z","synced":true}' "$1" "$2"; }
state() { local IFS=,; printf '{"version":1,"figma":{%s}}' "$*" > "$BRAIN/.sync-state.json"; }
filled() { mkdir -p "$BRAIN/$1"; echo x > "$BRAIN/$1/tokens.json"; }
gate() { (cd "$BRAIN" && bash "$GATE" "$@"); }
field() { printf '%s\n' "$1" | python3 -c 'import sys,json
for l in sys.stdin:
    d=json.loads(l)
    if d["id"]==sys.argv[1]: print(d[sys.argv[2]] if d[sys.argv[2]] is not None else "null"); break' "$2" "$3"; }
ncalls() { [ -f "$CURL_STUB_DIR/calls.log" ] && wc -l < "$CURL_STUB_DIR/calls.log" | tr -d ' ' || echo 0; }

# unchanged: one call, fingerprint carries version + lastModified
new_case unchanged; sources "$(entry ds KEYSAME out/ds/)"; state "$(slot KEYSAME 100)"; filled out/ds
o=$(gate)
[ "$(field "$o" ds status)" = unchanged ] || fail "unchanged: $o"
[ "$(ncalls)" = 1 ] || fail "unchanged figma source must log exactly one call (got $(ncalls))"
grep -q '^GET	https://api.figma.com/v1/files/KEYSAME?depth=1	X-Figma-Token: fake-token-for-tests' "$CURL_STUB_DIR/calls.log" || fail "call must carry the token header"
echo "$o" | grep -q '"fingerprint": {"version": "100", "lastModified": "2026-01-01T00:00:00Z"}' || fail "fingerprint shape: $o"

# changed
new_case changed; sources "$(entry ds KEYMOVED out/ds/)"; state "$(slot KEYMOVED 100)"; filled out/ds
o=$(gate); [ "$(field "$o" ds status)" = changed ] || fail "changed: $o"
echo "$o" | grep -q '"version": "200"' || fail "changed must carry the new version: $o"

# no token
new_case notoken; rm "$BRAIN/.env"; sources "$(entry ds KEYSAME out/ds/)"; state "$(slot KEYSAME 100)"; filled out/ds
o=$(gate); [ "$(field "$o" ds status)" = not-checked ] && [ "$(field "$o" ds reason)" = "no credentials" ] || fail "no token: $o"
[ "$(ncalls)" = 0 ] || fail "no token must make no call"

# offline (stub exit 7: no fixture for this key)
new_case offline; sources "$(entry ds KEYNOFIXTURE out/ds/)"; state "$(slot KEYNOFIXTURE 100)"; filled out/ds
o=$(gate); [ "$(field "$o" ds status)" = not-checked ] && [ "$(field "$o" ds reason)" = offline ] || fail "offline: $o"

# HTTP 403 names the status
new_case denied; sources "$(entry ds KEYDENIED out/ds/)"; state "$(slot KEYDENIED 100)"; filled out/ds
o=$(gate); [ "$(field "$o" ds status)" = not-checked ] || fail "403 status: $o"
[ "$(field "$o" ds reason)" = "HTTP 403" ] || fail "403 reason must name the status: $o"

# no slot -> never, no call
new_case noslot; sources "$(entry ds KEYSAME out/ds/)"; state; filled out/ds
o=$(gate); [ "$(field "$o" ds status)" = never ] || fail "no slot: $o"
[ "$(ncalls)" = 0 ] || fail "no slot needs no call"

# shared fileKey, tripped: one call, both entries changed
new_case shared; sources "$(entry a KEYMOVED out/a/)" "$(entry b KEYMOVED out/b/)"; state "$(slot KEYMOVED 100)"; filled out/a; filled out/b
o=$(gate)
[ "$(field "$o" a status)" = changed ] && [ "$(field "$o" b status)" = changed ] || fail "shared key: $o"
[ "$(ncalls)" = 1 ] || fail "shared key must make one call (got $(ncalls))"
[ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 2 ] || fail "one object per entry: $o"
# asking for one id widens to its sibling
o=$(gate a); [ "$(field "$o" b status)" = changed ] || fail "id must widen to sharing entries: $o"

# empty <into> on an unchanged key: never, sibling unchanged
new_case emptyinto; sources "$(entry a KEYSAME out/a/)" "$(entry b KEYSAME out/b/)"; state "$(slot KEYSAME 100)"; filled out/a; mkdir -p "$BRAIN/out/b"
o=$(gate)
[ "$(field "$o" a status)" = unchanged ] || fail "sibling must be unchanged: $o"
[ "$(field "$o" b status)" = never ] || fail "empty into must be never: $o"
[ "$(ncalls)" = 1 ] || fail "one call for the key"

# lone empty <into> on a stored key: never, and no call (nothing would read its result)
new_case loneempty; sources "$(entry b KEYSAME out/b/)"; state "$(slot KEYSAME 100)"; mkdir -p "$BRAIN/out/b"
o=$(gate)
[ "$(field "$o" b status)" = never ] || fail "lone empty into must be never: $o"
[ "$(ncalls)" = 0 ] || fail "lone empty into must make no call (got $(ncalls))"

# no ids: an entry with no "enabled" key is gated (enabled unless it says otherwise); false is not
new_case enabledkey; sources '{"id":"nokey","fileKey":"KEYSAME","into":"out/a/"}' '{"id":"off","fileKey":"KEYMOVED","into":"out/b/","enabled":false}'
state "$(slot KEYSAME 100)" "$(slot KEYMOVED 100)"; filled out/a; filled out/b
o=$(gate)
[ "$(field "$o" nokey status)" = unchanged ] || fail "entry without an enabled key must be gated with no ids: $o"
echo "$o" | grep -q '"off"' && fail "enabled:false must not be gated with no ids: $o"

# misuse: unknown id -> exit 1, no JSON
new_case misuse; sources "$(entry ds KEYSAME out/ds/)"; state
rc=0; o=$(gate nope 2>/dev/null) || rc=$?
[ "$rc" = 1 ] && [ -z "$o" ] || fail "unknown id must exit 1 with no stdout (rc=$rc)"

echo "PASS gate-figma"
