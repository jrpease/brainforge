#!/usr/bin/env bash
# Offline tests for scaffold/.brainforge/gate-website.sh against recorded responses
# (tests/fixtures/gates/website/*). curl and everything else is reached only via $TMP/bin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$TMP/bin" "$TMP/brain"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin/curl"
ln -s "$(command -v python3)" "$TMP/bin/python3"
PY="$TMP/bin/python3"
GATE="$ROOT/scaffold/.brainforge/gate-website.sh"
FX="$ROOT/tests/fixtures/gates/website"

cat > "$TMP/brain/sources.json" <<'J'
{"version":1,"websites":[
 {"id":"marketing","url":"https://www.example.test","sitemap":"https://www.example.test/sitemap.xml","into":"context/derived/web/","enabled":true},
 {"id":"noslot","url":"https://www.example.test","into":"context/derived/web2/","enabled":true}]}
J
cat > "$TMP/brain/.sync-state.json" <<'J'
{"version":1,"websites":{"marketing":{"synced":true,"urls":{
 "https://www.example.test/about":{"lastmod":"2026-09-01","etag":"\"about-1\""},
 "https://www.example.test/pricing":{"lastmod":"2026-09-02","etag":"\"pricing-1\""}}}}}
J
cp "$TMP/brain/.sync-state.json" "$TMP/state.before"

# run <fixture-dir-name> [ids...] -> $OUT (stdout); calls.log in $TMP/fx
run() {
  rm -rf "$TMP/fx"; mkdir -p "$TMP/fx"
  [ -d "$FX/$1" ] && cp "$FX/$1"/*.http "$TMP/fx/" 2>/dev/null || true
  local d=$1; shift
  OUT=$(cd "$TMP/brain" && CURL_STUB_DIR="$TMP/fx" PATH="$TMP/bin:/usr/bin:/bin" bash "$GATE" "$@")
  : "$d"
}
# j '<python expr over d (first line object)>' -> prints result
j() { printf '%s\n' "$OUT" | head -n 1 | $PY -c 'import sys,json; d=json.loads(sys.stdin.readline()); print(eval(sys.argv[1]))' "$1"; }
calls() { if [ -f "$TMP/fx/calls.log" ]; then wc -l < "$TMP/fx/calls.log" | tr -d ' '; else echo 0; fi; }

# (1) unchanged: one sitemap fetch, every other call a conditional GET answered 304
run unchanged marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "unchanged: status ($OUT)"
[ "$(j 'd["type"]')" = website ] || fail "unchanged: type must be the adapter name, website ($OUT)"
[ "$(j 'd["delta"]')" = "[]" ] || fail "unchanged: delta must be empty"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/about"]["etag"]')" = '"about-1"' ] || fail "unchanged: fingerprint must carry the stored etag"
[ "$(calls)" = 3 ] || fail "unchanged: expected 3 calls (1 sitemap + 2 conditional), got $(calls)"
[ "$(grep -c 'sitemap\.xml' "$TMP/fx/calls.log")" = 1 ] || fail "unchanged: exactly one sitemap fetch"
n304=$(grep -v 'sitemap\.xml' "$TMP/fx/calls.log" | grep -c 'If-None-Match: "' || true)
[ "$n304" = 2 ] || fail "unchanged: every non-sitemap call must be a conditional GET (got $n304)"
# the conditional GET sends the stored etag and validator
grep -q 'example.test/about	.*If-None-Match: "about-1"' "$TMP/fx/calls.log" || fail "conditional GET must send the stored etag"
grep -q 'example.test/about	.*If-Modified-Since: Tue, 01 Sep 2026 00:00:00 GMT' "$TMP/fx/calls.log" || fail "conditional GET must send If-Modified-Since as the HTTP-date of the stored lastmod"
[ "$(cat "$TMP/brain/.sync-state.json")" = "$(cat "$TMP/state.before")" ] || fail "gate must not write .sync-state.json"

# (2) changed lastmod + a new URL: both in delta, etag null, no fetch of the page itself
run changed marketing
[ "$(j 'd["status"]')" = changed ] || fail "changed: status ($OUT)"
[ "$(j 'sorted(d["delta"])')" = "['https://www.example.test/blog/new', 'https://www.example.test/pricing']" ] || fail "changed: delta ($(j 'd["delta"]'))"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]')" = "{'lastmod': '2026-10-05', 'etag': None}" ] || fail "changed: delta URL fingerprint must carry new lastmod and etag null"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/about"]["etag"]')" = '"about-1"' ] || fail "changed: skipped URL keeps etag"
[ "$(calls)" = 2 ] || fail "changed: expected sitemap + 1 conditional GET only, got $(calls)"

# (3) matching lastmod but the conditional GET returns 200 -> delta
run cond200 marketing
[ "$(j 'd["status"]')" = changed ] || fail "cond200: status ($OUT)"
[ "$(j 'd["delta"]')" = "['https://www.example.test/pricing']" ] || fail "cond200: delta ($(j 'd["delta"]'))"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["etag"]')" = None ] || fail "cond200: delta URL etag must be null"

# (4) URL with no <lastmod> gets the conditional GET; 304 skips it
run nolastmod marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "nolastmod: status ($OUT)"
grep -q 'example.test/about	.*If-None-Match: "about-1"' "$TMP/fx/calls.log" || fail "nolastmod: must send the conditional GET"

# (4b) stored etag null (a site that sends no ETag): only If-Modified-Since can earn the 304, so
# it must be a valid HTTP-date (RFC 7232 3.3: a server ignores any other value). W3C dates with
# Z and with an offset convert to GMT; an unparseable lastmod sends no If-Modified-Since at all.
cp "$TMP/brain/.sync-state.json" "$TMP/state.keep"
cat > "$TMP/brain/.sync-state.json" <<'J'
{"version":1,"websites":{"marketing":{"synced":true,"urls":{
 "https://www.example.test/about":{"lastmod":"2026-09-01T10:00:00Z","etag":null},
 "https://www.example.test/pricing":{"lastmod":"2026-09-02T10:00:00+02:00","etag":null},
 "https://www.example.test/team":{"lastmod":"not-a-date","etag":null}}}}}
J
run noetag marketing
cp "$TMP/state.keep" "$TMP/brain/.sync-state.json"
[ "$(j 'd["status"]')" = unchanged ] || fail "noetag: 304 on If-Modified-Since alone must be unchanged ($OUT)"
grep -q 'If-None-Match' "$TMP/fx/calls.log" && fail "noetag: no stored etag, so no If-None-Match"
ims=$(grep -v 'sitemap\.xml' "$TMP/fx/calls.log" | grep -o 'If-Modified-Since: [^;	]*' | sed 's/^If-Modified-Since: //')
[ "$(printf '%s\n' "$ims" | grep -c .)" = 2 ] || fail "noetag: expected If-Modified-Since on 2 calls (got: $ims)"
printf '%s\n' "$ims" | grep -Evq '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$' && fail "noetag: If-Modified-Since must be an HTTP-date (got: $ims)"
grep -q 'example.test/about	.*If-Modified-Since: Tue, 01 Sep 2026 10:00:00 GMT' "$TMP/fx/calls.log" || fail "noetag: Z lastmod must convert to its HTTP-date"
grep -q 'example.test/pricing	.*If-Modified-Since: Wed, 02 Sep 2026 08:00:00 GMT' "$TMP/fx/calls.log" || fail "noetag: offset lastmod must convert to GMT"
grep 'example.test/team	' "$TMP/fx/calls.log" | grep -q 'If-Modified-Since' && fail "noetag: unparseable lastmod must send no If-Modified-Since"

# (5) stub exit 7 -> not-checked (offline)
run offline marketing
[ "$(j 'd["status"]')" = not-checked ] && [ "$(j 'd["reason"]')" = offline ] || fail "offline ($OUT)"

# (6) HTTP 403 on the sitemap -> not-checked naming the status
run forbidden marketing
[ "$(j 'd["status"]')" = not-checked ] || fail "403: status ($OUT)"
case "$(j 'd["reason"]')" in *403*) ;; *) fail "403: reason must name the status ($OUT)" ;; esac

# (7) no stored slot -> never, with no call at all
run unchanged noslot
[ "$(j 'd["status"]')" = never ] || fail "no slot: status ($OUT)"
[ "$(calls)" = 0 ] || fail "no slot: must make no call"

# (8) no ids -> every enabled entry, one JSON line each; sitemap defaults to <url>/sitemap.xml
rm -f "$TMP/brain/x"; $PY - "$TMP/brain/sources.json" <<'P'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); del d["websites"][0]["sitemap"]; json.dump(d,open(p,"w"))
P
run unchanged
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ] || fail "no ids: expected 2 lines ($OUT)"
[ "$(printf '%s\n' "$OUT" | sed -n 2p | $PY -c 'import sys,json; print(json.loads(sys.stdin.readline())["status"])')" = never ] || fail "no ids: second line is noslot -> never"
[ "$(j 'd["status"]')" = unchanged ] || fail "default sitemap path: status ($OUT)"

# (9) misuse: unknown id -> exit 1, nothing on stdout
rc=0; out=$(cd "$TMP/brain" && CURL_STUB_DIR="$TMP/fx" PATH="$TMP/bin:/usr/bin:/bin" bash "$GATE" nope 2>/dev/null) || rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] || fail "unknown id must exit 1 with no stdout (rc=$rc)"

echo "PASS gate-website"
