#!/usr/bin/env bash
# Offline test for scaffold/.brainforge/gate-ga.sh: recorded runReport responses via the curl stub,
# a gcloud stub that prints a fake token, PATH holds only the stub dir plus the system dirs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/scaffold/.brainforge/gate-ga.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin/curl"
ln -s "$(command -v python3)" "$TMP/bin/python3"
cat > "$TMP/bin/gcloud" <<'SH'
#!/usr/bin/env bash
echo "args=$* GAC=${GOOGLE_APPLICATION_CREDENTIALS-<unset>}" >> "$GCLOUD_LOG"
echo "fake-token-for-tests"
SH
chmod +x "$TMP/bin/gcloud"
unset GOOGLE_APPLICATION_CREDENTIALS
export PATH="$TMP/bin:/usr/bin:/bin"

# fresh brain + fixture dir per case: new_case <name> -> sets BRAIN, CURL_STUB_DIR, GCLOUD_LOG
new_case() {
  BRAIN="$TMP/$1"; mkdir -p "$BRAIN"; CURL_STUB_DIR="$TMP/$1-fx"; mkdir -p "$CURL_STUB_DIR"
  cp "$ROOT"/tests/fixtures/gates/ga/*.http "$CURL_STUB_DIR/"; export CURL_STUB_DIR
  GCLOUD_LOG="$TMP/$1-gcloud.log"; : > "$GCLOUD_LOG"; export GCLOUD_LOG
}
# entry <id> <propertyId> -> JSON object
entry() { printf '{"id":"%s","propertyId":"%s","lookbackDays":3,"into":"context/derived/ga/","enabled":true}' "$1" "$2"; }
sources() { local IFS=,; printf '{"version":1,"ga":[%s]}' "$*" > "$BRAIN/sources.json"; }
# slot <propertyId>: stored through 2026-10-03, last 3 days of sessions
slot() { printf '"%s":{"lastSyncedThrough":"2026-10-03","trailingSessionHashes":{"20261001":100,"20261002":110,"20261003":120},"synced":true}' "$1"; }
state() { local IFS=,; printf '{"version":1,"ga":{%s}}' "$*" > "$BRAIN/.sync-state.json"; }
gate() { (cd "$BRAIN" && bash "$GATE" "$@"); }
field() { printf '%s\n' "$1" | python3 -c 'import sys,json
for l in sys.stdin:
    d=json.loads(l)
    if d["id"]==sys.argv[1]: v=d[sys.argv[2]]; print("null" if v is None else (json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v)); break' "$2" "$3"; }
ncalls() { [ -f "$CURL_STUB_DIR/calls.log" ] && wc -l < "$CURL_STUB_DIR/calls.log" | tr -d ' ' || echo 0; }

# unchanged: no new date, equal sessions; one call, window and token as documented
new_case unchanged; sources "$(entry web 1001)"; state "$(slot 1001)"
o=$(gate)
[ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] || fail "one JSON line per entry: $o"
[ "$(field "$o" web status)" = unchanged ] || fail "unchanged: $o"
[ "$(field "$o" web delta)" = "[]" ] || fail "unchanged delta must be empty: $o"
[ "$(field "$o" web fingerprint)" = '{"lastSyncedThrough": "2026-10-03", "trailingSessionHashes": {"20261001": 100, "20261002": 110, "20261003": 120}}' ] \
  || fail "unchanged fingerprint must equal the stored shape: $(field "$o" web fingerprint)"
[ "$(ncalls)" = 1 ] || fail "unchanged GA source must log exactly one call (got $(ncalls))"
grep -q '^POST	https://analyticsdata.googleapis.com/v1beta/properties/1001:runReport	Authorization: Bearer fake-token-for-tests' "$CURL_STUB_DIR/calls.log" \
  || fail "call must carry the gcloud token as a Bearer header"

# endDate is the literal "yesterday"; startDate = lastSyncedThrough - lookbackDays
grep -q '"dateRanges":\[{"startDate":"2026-09-30","endDate":"yesterday"}\]' "$CURL_STUB_DIR/calls.log" \
  || fail "request must send startDate 2026-09-30 and endDate \"yesterday\": $(cat "$CURL_STUB_DIR/calls.log")"
grep -q '"metrics":\[{"name":"sessions"}\]' "$CURL_STUB_DIR/calls.log" || fail "request must ask for sessions"
grep -q 'GAC=<unset>' "$GCLOUD_LOG" || fail "no GOOGLE_APPLICATION_CREDENTIALS in .env -> gcloud must run without it: $(cat "$GCLOUD_LOG")"
grep -q 'args=auth application-default print-access-token' "$GCLOUD_LOG" || fail "gcloud must run print-access-token"

# late-arriving revision to one day -> changed, delta = that date
new_case restated; sources "$(entry web 1002)"; state "$(slot 1002)"
o=$(gate)
[ "$(field "$o" web status)" = changed ] || fail "restated: $o"
[ "$(field "$o" web delta)" = '["2026-10-02"]' ] || fail "restated delta must be only that date: $o"
field "$o" web fingerprint | grep -q '"20261002": 115' || fail "fingerprint must carry the restated sessions: $o"

# a new day -> changed, delta = the new date, lastSyncedThrough = maxDate
new_case newday; sources "$(entry web 1003)"; state "$(slot 1003)"
o=$(gate)
[ "$(field "$o" web status)" = changed ] || fail "new day: $o"
[ "$(field "$o" web delta)" = '["2026-10-04"]' ] || fail "new day delta: $o"
[ "$(field "$o" web fingerprint)" = '{"lastSyncedThrough": "2026-10-04", "trailingSessionHashes": {"20261002": 110, "20261003": 120, "20261004": 130}}' ] \
  || fail "new-day fingerprint must advance to maxDate and keep the last lookbackDays: $(field "$o" web fingerprint)"

# GOOGLE_APPLICATION_CREDENTIALS in .env -> exported to gcloud
new_case sakey; sources "$(entry web 1001)"; state "$(slot 1001)"
printf 'OTHER=1\nGOOGLE_APPLICATION_CREDENTIALS="/keys/sa-test.json"\n' > "$BRAIN/.env"
o=$(gate); [ "$(field "$o" web status)" = unchanged ] || fail "sa key: $o"
grep -q 'GAC=/keys/sa-test.json' "$GCLOUD_LOG" || fail "gcloud must see GOOGLE_APPLICATION_CREDENTIALS exported: $(cat "$GCLOUD_LOG")"

# no gcloud on PATH -> not-checked (no credentials), no call
new_case nogcloud; sources "$(entry web 1001)"; state "$(slot 1001)"
mkdir -p "$TMP/bin-nogcloud"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin-nogcloud/curl"
ln -s "$(command -v python3)" "$TMP/bin-nogcloud/python3"
o=$(cd "$BRAIN" && PATH="$TMP/bin-nogcloud:/usr/bin:/bin" bash "$GATE")
[ "$(field "$o" web status)" = not-checked ] && [ "$(field "$o" web reason)" = "no credentials" ] || fail "no gcloud: $o"
[ "$(ncalls)" = 0 ] || fail "no gcloud must make no call"

# gcloud present but print-access-token fails -> not-checked (no credentials), no call
new_case gcloudfail; sources "$(entry web 1001)"; state "$(slot 1001)"
mkdir -p "$TMP/bin-gcloudfail"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin-gcloudfail/curl"
ln -s "$(command -v python3)" "$TMP/bin-gcloudfail/python3"
printf '#!/usr/bin/env bash\necho "ERROR: no application default credentials" >&2\nexit 1\n' > "$TMP/bin-gcloudfail/gcloud"
chmod +x "$TMP/bin-gcloudfail/gcloud"
o=$(cd "$BRAIN" && PATH="$TMP/bin-gcloudfail:/usr/bin:/bin" bash "$GATE")
[ "$(field "$o" web status)" = not-checked ] && [ "$(field "$o" web reason)" = "no credentials" ] || fail "gcloud fails: $o"
[ "$(ncalls)" = 0 ] || fail "failed gcloud must make no call"

# no stored slot -> never, zero calls (curl or gcloud)
new_case noslot; sources "$(entry web 1001)"; state
o=$(gate); [ "$(field "$o" web status)" = never ] || fail "no slot: $o"
[ "$(ncalls)" = 0 ] || fail "no slot must make zero calls (got $(ncalls))"
[ ! -s "$GCLOUD_LOG" ] || fail "no slot must not ask gcloud for a token"

# offline (stub exit 7: no fixture for this property) and HTTP 403
new_case offline; sources "$(entry web 9999)"; state "$(slot 9999)"
o=$(gate); [ "$(field "$o" web status)" = not-checked ] && [ "$(field "$o" web reason)" = offline ] || fail "offline: $o"
new_case denied; sources "$(entry web 1004)"; state "$(slot 1004)"
o=$(gate); [ "$(field "$o" web status)" = not-checked ] && [ "$(field "$o" web reason)" = "HTTP 403" ] || fail "403: $o"

# no ids gates every enabled entry; an id gates just that one; unknown id is misuse
new_case multi
sources "$(entry a 1001)" "$(entry b 1003)" '{"id":"off","propertyId":"1002","into":"context/derived/ga/","enabled":false}'
state "$(slot 1001)" "$(slot 1003)" "$(slot 1002)"
o=$(gate)
[ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 2 ] || fail "no ids must gate the two enabled entries: $o"
[ "$(field "$o" a status)" = unchanged ] && [ "$(field "$o" b status)" = changed ] || fail "multi: $o"
o=$(gate b); [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] && [ "$(field "$o" b status)" = changed ] || fail "single id: $o"
rc=0; gate nope >/dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail "unknown id must exit 1 (got $rc)"
rm "$BRAIN/sources.json"; rc=0; gate >/dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail "no sources.json must exit 1 (got $rc)"

# read-only: the state file is untouched
new_case readonly; sources "$(entry web 1003)"; state "$(slot 1003)"
before=$(cat "$BRAIN/.sync-state.json"); gate >/dev/null
[ "$(cat "$BRAIN/.sync-state.json")" = "$before" ] || fail "gate must never write .sync-state.json"

echo "PASS gate-ga"
