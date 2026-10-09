#!/usr/bin/env bash
# Self-test for tests/lib/curl-stub.sh: match, no-match -> 7, status via -w, and the call log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$TMP/bin" "$TMP/fx"; ln -s "$ROOT/tests/lib/curl-stub.sh" "$TMP/bin/curl"
export CURL_STUB_DIR="$TMP/fx" PATH="$TMP/bin:/usr/bin:/bin"

printf '# match: GET ^https://api\\.example\\.test/v1/files/abc\nHELLO\n' > "$TMP/fx/a.http"
printf '# match: POST ^https://api\\.example\\.test/graphql "ids":\\["7"\\]\n# status: 403\n# header: ETag: "e1"\n{"err":1}\n' > "$TMP/fx/b.http"

[ "$(command -v curl)" = "$TMP/bin/curl" ] && [ -x "$TMP/bin/curl" ] || fail "curl on PATH must be the executable stub"

# match: body printed
out=$(curl -s -H 'X-Token: t' https://api.example.test/v1/files/abc)
[ "$out" = "HELLO" ] || fail "GET match must print the recorded body (got: $out)"

# match on POST body, status via -w, header dump, -o
out=$(curl -s -X POST -d '{"ids":["7"]}' -D "$TMP/h" -o "$TMP/o" -w '%{http_code}' https://api.example.test/graphql)
[ "$out" = "403" ] || fail "-w must print the recorded status (got: $out)"
[ "$(cat "$TMP/o")" = '{"err":1}' ] || fail "-o must receive the body"
grep -q '^ETag: "e1"' "$TMP/h" || fail "-D must receive the recorded header"

# no match -> exit 7, nothing printed
rc=0; out=$(curl -s https://api.example.test/nothing) || rc=$?
[ "$rc" -eq 7 ] || fail "no fixture must exit 7 (got $rc)"
[ -z "$out" ] || fail "no match must print nothing"
rc=0; curl -s -X POST -d '{"ids":["8"]}' https://api.example.test/graphql >/dev/null || rc=$?
[ "$rc" -eq 7 ] || fail "body regex must be enforced (got $rc)"

rc=0; curl -s -X GET -d '{"ids":["7"]}' https://api.example.test/graphql >/dev/null || rc=$?
[ "$rc" -eq 7 ] || fail "method must be enforced (got $rc)"
out=$(curl -s -w '%{http_code}' https://api.example.test/v1/files/abc)
[ "$out" = "HELLO
200" ] || fail "status must default to 200 (got: $out)"

# call log: every call, matched or not
[ "$(wc -l < "$TMP/fx/calls.log" | tr -d ' ')" = 6 ] || fail "calls.log must hold all 6 calls"
grep -q "^GET	https://api.example.test/v1/files/abc	X-Token: t	" "$TMP/fx/calls.log" || fail "calls.log must record method, url, headers"
grep -q '"ids":\["8"\]' "$TMP/fx/calls.log" || fail "calls.log must record the body"

echo "PASS gate-harness"
