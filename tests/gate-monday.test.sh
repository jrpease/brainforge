#!/usr/bin/env bash
# Offline test for scaffold/.brainforge/gate-monday.sh against recorded GraphQL responses
# (tests/fixtures/gates/monday/). No network, no credentials: curl is the test stub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/scaffold/.brainforge/gate-monday.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin/curl"
export PATH="$TMP/bin:/usr/bin:/bin"
[ "$(command -v curl)" = "$TMP/bin/curl" ] || fail "curl on PATH must be the stub"

# A fresh brain + fixture dir per case. Board 1001 unchanged, 1002 edited in place (only the
# newest activity moved), 1003 a pre-upgrade slot with no lastActivityAt and empty activity_logs.
new_brain() {
  B="$TMP/brain-$1"; rm -rf "$B"; mkdir -p "$B/fx"
  cp "$ROOT"/tests/fixtures/gates/monday/*.http "$B/fx/"
  export CURL_STUB_DIR="$B/fx"
  printf 'OTHER=x\nMONDAY_API_TOKEN=test-token-not-real\n' > "$B/.env"
  cat > "$B/sources.json" <<'EOF'
{ "version": 1, "monday": [
  {"id":"roadmap","boardId":"1001","into":"context/derived/monday/","enabled":true},
  {"id":"tasks","boardId":"1002","into":"context/derived/monday/","enabled":true},
  {"id":"legacy","boardId":"1003","into":"context/derived/monday/","enabled":true},
  {"id":"fresh","boardId":"1004","into":"context/derived/monday/","enabled":false},
  {"id":"broken","boardId":"9999","into":"context/derived/monday/","enabled":false},
  {"id":"flaky","boardId":"5000","into":"context/derived/monday/","enabled":false}
] }
EOF
  cat > "$B/.sync-state.json" <<'EOF'
{
  "version": 1,
  "monday": {
    "1001": {
      "updated_at": "2026-10-01T09:00:00Z",
      "items_count": 42,
      "lastActivityAt": "17592000000000000",
      "synced": true
    },
    "1002": {
      "updated_at": "2026-10-01T09:00:00Z",
      "items_count": 7,
      "lastActivityAt": "17591000000000000",
      "synced": true
    },
    "1003": {
      "updated_at": "2026-09-20T12:00:00Z",
      "items_count": 3,
      "synced": true
    },
    "1004": {
      "synced": false
    }
  },
  "lastFullSync": "2026-10-01"
}
EOF
}
run() { (cd "$B" && bash "$GATE" "$@"); }
# field <json-lines> <id> <python-expr on o> — print one value from the line for <id>
field() {
  printf '%s\n' "$1" | python3 -c '
import json, sys
want, expr = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in sys.stdin if l.strip()]
hit = [o for o in rows if o["id"] == want]
if len(hit) != 1: print("<%d rows for %s>" % (len(hit), want)); sys.exit()
o = hit[0]; print(json.dumps(eval(expr)))' "$2" "$3"
}
calls() { if [ -f "$CURL_STUB_DIR/calls.log" ]; then wc -l < "$CURL_STUB_DIR/calls.log" | tr -d ' '; else echo 0; fi; }

# 1. No ids: every enabled entry (three) in exactly one call, three JSON lines.
new_brain all
out=$(run)
[ "$(printf '%s\n' "$out" | grep -c .)" = 3 ] || fail "no ids must print 3 lines (got: $out)"
[ "$(calls)" = 1 ] || fail "three boards must cost exactly one call (got $(calls))"
log=$(cat "$CURL_STUB_DIR/calls.log")
printf '%s' "$log" | grep -q '"ids": \["1001", "1002", "1003"\]' || fail "the one call must carry all three boardIds (log: $log)"
printf '%s' "$log" | grep -q 'Authorization: test-token-not-real' || fail "the call must send the .env token"
printf '%s' "$log" | grep -q '^POST	https://api.monday.com/v2	' || fail "the call must POST to the monday endpoint"
printf '%s' "$out" | grep -q '"fresh"\|"broken"\|"flaky"' && fail "disabled entries must not be gated with no ids"

# 2. All three fields match -> unchanged, empty delta.
[ "$(field "$out" roadmap 'o["status"]')" = '"unchanged"' ] || fail "matching fingerprint must be unchanged (got: $out)"
[ "$(field "$out" roadmap 'o["delta"]')" = '[]' ] || fail "unchanged must have an empty delta"
[ "$(field "$out" roadmap 'o["type"]')" = '"monday"' ] || fail "type must be monday"
[ "$(field "$out" roadmap 'o["fingerprint"]')" = '{"updated_at": "2026-10-01T09:00:00Z", "items_count": 42, "lastActivityAt": "17592000000000000"}' ] \
  || fail "fingerprint must be the widened triple (got: $(field "$out" roadmap 'o["fingerprint"]'))"

# 3. Only lastActivityAt moved (the in-place-edit case) -> changed.
[ "$(field "$out" tasks 'o["status"]')" = '"changed"' ] || fail "in-place edit (only lastActivityAt moved) must be changed (got: $out)"
[ "$(field "$out" tasks 'o["delta"]')" = '["lastActivityAt"]' ] || fail "delta must name lastActivityAt only"

# 4 + 5. Pre-upgrade slot without lastActivityAt -> changed; empty activity_logs -> null, no crash.
[ "$(field "$out" legacy 'o["status"]')" = '"changed"' ] || fail "slot without lastActivityAt must be changed"
[ "$(field "$out" legacy 'o["fingerprint"]["lastActivityAt"]')" = 'null' ] || fail "empty activity_logs must give lastActivityAt null"
[ "$(field "$out" legacy 'o["delta"]')" = '["lastActivityAt"]' ] || fail "legacy delta must be lastActivityAt"

# 6. A slot with no fingerprint yet (written by /add-source) -> never, fingerprint still reported.
new_brain never
out=$(run fresh)
[ "$(field "$out" fresh 'o["status"]')" = '"never"' ] || fail "slot without a fingerprint must be never (got: $out)"
[ "$(field "$out" fresh 'o["fingerprint"]["items_count"]')" = '12' ] || fail "never must still carry the fingerprint for §3"

# 7. GraphQL errors array -> not-checked with the first message, for every entry in the call.
new_brain err
out=$(run broken)
[ "$(field "$out" broken 'o["status"]')" = '"not-checked"' ] || fail "GraphQL error must be not-checked (got: $out)"
[ "$(field "$out" broken 'o["reason"]')" = '"GraphQL error: Board not found or no access"' ] || fail "reason must carry the first error message"
new_brain err2
out=$(run broken roadmap)
[ "$(printf '%s\n' "$out" | grep -c '"not-checked"')" = 2 ] || fail "a GraphQL error must make every entry in the call not-checked (got: $out)"
[ "$(calls)" = 1 ] || fail "two ids must still be one call"

# 8. No token -> not-checked (no credentials), and no call made.
new_brain notoken
printf 'OTHER=x\n# MONDAY_API_TOKEN=commented\n' > "$B/.env"
out=$(run roadmap)
[ "$(field "$out" roadmap 'o["reason"]')" = '"no credentials"' ] || fail "missing token must be no credentials (got: $out)"
[ "$(calls)" = 0 ] || fail "missing token must make no call"

# 9. Stub exit 7 (no fixture) -> not-checked (offline). HTTP 500 -> reason names the status.
new_brain offline
rm "$B"/fx/*.http
out=$(run roadmap)
[ "$(field "$out" roadmap 'o["status"]')" = '"not-checked"' ] && [ "$(field "$out" roadmap 'o["reason"]')" = '"offline"' ] || fail "curl exit 7 must be not-checked (offline) (got: $out)"
new_brain http
out=$(run flaky)
[ "$(field "$out" flaky 'o["reason"]')" = '"HTTP 500"' ] || fail "HTTP 500 must be not-checked naming the status (got: $out)"

# 10. Misuse exits 1: unknown id, no sources.json. Read-only: state file untouched.
new_brain misuse
rc=0; run nope >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "unknown id must exit 1 (got $rc)"
before=$(cat "$B/.sync-state.json"); run >/dev/null
[ "$(cat "$B/.sync-state.json")" = "$before" ] || fail "the gate must never write .sync-state.json"
rm "$B/sources.json"; rc=0; run >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "no sources.json must exit 1 (got $rc)"

# 10b. No ids: an entry with no "enabled" key is gated (enabled unless it says otherwise).
new_brain nokey
python3 - "$B/sources.json" <<'PYX'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); del d["monday"][0]["enabled"]; json.dump(d, open(p, "w"))
PYX
out=$(run)
[ "$(field "$out" roadmap 'o["status"]')" = '"unchanged"' ] || fail "entry without an enabled key must be gated with no ids (got: $out)"

echo "PASS gate-monday"
