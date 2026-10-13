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
# H(b"...") is the sha256 of literal bytes: expected hashes are computed here, never captured from
# a gate run, so a gate hashing the wrong thing cannot agree with them by construction.
j() { printf '%s\n' "$OUT" | head -n 1 | $PY -c 'import sys,json,hashlib; H=lambda b: hashlib.sha256(b).hexdigest(); d=json.loads(sys.stdin.readline()); print(eval(sys.argv[1]))' "$1"; }
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

# (2) changed lastmod + a new URL: both in delta, each downloaded once, so the fingerprint is complete
run changed marketing
[ "$(j 'd["status"]')" = changed ] || fail "changed: status ($OUT)"
[ "$(j 'sorted(d["delta"])')" = "['https://www.example.test/blog/new', 'https://www.example.test/pricing']" ] || fail "changed: delta ($(j 'd["delta"]'))"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"] == {"lastmod": "2026-10-05", "etag": "\"pricing-2\"", "sha256": H(b"pricing v2\n")}')" = True ] || fail "changed: delta URL fingerprint must carry the new lastmod, etag and hash ($(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]'))"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/blog/new"]["sha256"] == H(b"a new post\n")')" = True ] || fail "changed: a new URL is downloaded and hashed"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/about"]["etag"]')" = '"about-1"' ] || fail "changed: skipped URL keeps etag"
[ "$(calls)" = 4 ] || fail "changed: expected sitemap + 1 conditional + 2 downloads, got $(calls)"
grep 'example.test/pricing	' "$TMP/fx/calls.log" | grep -q 'If-None-Match' && fail "changed: a changed lastmod is an unconditional download"

# (3) matching lastmod but the conditional GET returns 200 -> delta
run cond200 marketing
[ "$(j 'd["status"]')" = changed ] || fail "cond200: status ($OUT)"
[ "$(j 'd["delta"]')" = "['https://www.example.test/pricing']" ] || fail "cond200: delta ($(j 'd["delta"]'))"
# (3b) legacy state, no stored sha256: a 200 is a delta, as before this fix, and records the hash
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"] == {"lastmod": "2026-09-02", "etag": "\"pricing-2\"", "sha256": H(b"")}')" = True ] || fail "cond200: delta URL takes the 200's etag and hash ($(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]'))"
[ "$(calls)" = 3 ] || fail "cond200: the conditional GET's own body is hashed, not fetched again (got $(calls))"

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

# (10) content hashing. State: both pages carry the hash of what was served last time.
cp "$TMP/brain/.sync-state.json" "$TMP/state.keep"
$PY - "$TMP/brain/.sync-state.json" <<'P'
import hashlib, json, sys
H = lambda b: hashlib.sha256(b).hexdigest()
json.dump({"version": 1, "websites": {"marketing": {"synced": True, "urls": {
  "https://www.example.test/about": {"lastmod": "2026-09-01", "etag": "\"about-1\"", "sha256": H(b"about body\n")},
  "https://www.example.test/pricing": {"lastmod": "2026-09-02", "etag": "\"pricing-a\"", "sha256": H(b"pricing body\n")}}}}},
  open(sys.argv[1], "w"))
P
# (10a) a CDN flap: another origin's ETag, identical bytes -> unchanged, new etag kept, same hash
run flap marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "flap: identical bytes under another ETag must be unchanged ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"] == {"lastmod": "2026-09-02", "etag": "\"pricing-b\"", "sha256": H(b"pricing body\n")}')" = True ] || fail "flap: fingerprint ($(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]'))"
# (10c) a 304 keeps the stored hash, or the next flap would read changed again
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/about"]["sha256"] == H(b"about body\n")')" = True ] || fail "304: must keep the stored sha256"
# (10b) another ETag and different bytes -> delta with the new hash
run flapchanged marketing
[ "$(j 'd["status"]')" = changed ] && [ "$(j 'd["delta"]')" = "['https://www.example.test/pricing']" ] || fail "flapchanged: different bytes must be a delta ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["sha256"] == H(b"pricing body, new price\n")')" = True ] || fail "flapchanged: delta carries the new hash"
# (10e) a bumped <lastmod> over identical bytes -> unchanged, the new lastmod stored
run lastmodbump marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "lastmodbump: identical bytes under a new lastmod must be unchanged ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["lastmod"]')" = 2026-10-05 ] || fail "lastmodbump: must store the new lastmod"
# (10f) an error page whose body happens to match the stored hash is never "unchanged": only a 2xx
# body is hashed, so a stable 500 cannot read as current sync after sync
run errpage marketing
[ "$(j 'd["status"]')" = changed ] || fail "errpage: a 500 must be a delta ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]')" = "{'lastmod': '2026-09-02', 'etag': None, 'sha256': None}" ] || fail "errpage: non-2xx carries null validators"
# (10g) a 3xx that does not resolve (no Location) is not a 304: a delta, never skipped on the stale hash
run moved marketing
[ "$(j 'd["status"]')" = changed ] || fail "moved: a 301 must be a delta ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["sha256"]')" = None ] || fail "moved: a 3xx body is not hashed"
# (10h) a redirect that resolves (301 -> 200, identical bytes) is followed: the final page is
# hashed, its etag kept (not the redirect hop's), so a trailing-slash redirect is not a delta forever
run redirect marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "redirect: a 301 to identical bytes must be unchanged ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"] == {"lastmod": "2026-09-02", "etag": "\"pricing-final\"", "sha256": H(b"pricing body\n")}')" = True ] || fail "redirect: fingerprint must carry the final page's etag and hash ($(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]'))"
grep -q 'example.test/pricing/	.*If-None-Match: "pricing-a"' "$TMP/fx/calls.log" || fail "redirect: the conditional headers must reach the final hop"
# (10i) a followed conditional GET that earns a 304 at the target is unchanged, etag from that hop
run redirect304 marketing
[ "$(j 'd["status"]')" = unchanged ] || fail "redirect304: a 301 to a 304 must be unchanged ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["etag"]')" = '"pricing-final"' ] || fail "redirect304: etag from the final hop"
# (10j) --fingerprint follows it too
run redirect --fingerprint marketing
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/pricing"]["sha256"] == H(b"pricing body\n")')" = True ] || fail "fingerprint: a redirected page is hashed at its target"
cp "$TMP/state.keep" "$TMP/brain/.sync-state.json"

# (11) one page that cannot be downloaded never fails the site: it is a delta with null validators
run missingpage marketing
[ "$(j 'd["status"]')" = changed ] || fail "missingpage: the entry must still be changed, not not-checked ($OUT)"
[ "$(j 'd["fingerprint"]["urls"]["https://www.example.test/blog/new"]')" = "{'lastmod': '2026-10-06', 'etag': None, 'sha256': None}" ] || fail "missingpage: failed download carries null validators"
[ "$(j '"https://www.example.test/blog/new" in d["delta"]')" = True ] || fail "missingpage: failed download is in the delta"

# (12) --fingerprint: every sitemap URL downloaded once, unconditionally; works with no stored slot
run full --fingerprint marketing
[ "$(j 'd["status"]')" = fingerprint ] && [ "$(j 'd["delta"]')" = "[]" ] || fail "fingerprint: status/delta ($OUT)"
[ "$(j 'd["fingerprint"]["urls"] == {"https://www.example.test/about": {"lastmod": "2026-09-01", "etag": "\"about-1\"", "sha256": H(b"about body\n")}, "https://www.example.test/pricing": {"lastmod": "2026-09-02", "etag": "\"pricing-a\"", "sha256": H(b"pricing body\n")}}')" = True ] || fail "fingerprint: full map ($(j 'd["fingerprint"]'))"
[ "$(calls)" = 3 ] || fail "fingerprint: sitemap + one download per URL (got $(calls))"
grep -q 'If-None-Match\|If-Modified-Since' "$TMP/fx/calls.log" && fail "fingerprint: downloads must be unconditional"
run full --fingerprint noslot
[ "$(j 'd["status"]')" = fingerprint ] || fail "fingerprint: a never-synced source must fingerprint, not print never ($OUT)"
[ "$(j 'd["stored"]')" = None ] || fail "fingerprint: a slot-less entry reports stored null, per the contract"
for args in "--fingerprint" "--fingerprint marketing noslot" "--fingerprint nope"; do
  rc=0; out=$(cd "$TMP/brain" && CURL_STUB_DIR="$TMP/fx" PATH="$TMP/bin:/usr/bin:/bin" bash "$GATE" $args 2>/dev/null) || rc=$?
  [ "$rc" = 1 ] && [ -z "$out" ] || fail "misuse '$args' must exit 1 with no stdout (rc=$rc)"
done

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
