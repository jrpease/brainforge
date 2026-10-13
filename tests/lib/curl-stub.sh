#!/usr/bin/env bash
# Test-only curl stand-in. Link it into place as $TMP/bin/curl and put $TMP/bin first on PATH.
# Needs CURL_STUB_DIR: a directory of *.http fixtures (format: tests/fixtures/gates/README.md).
# Parses -X, -d/--data, -H, -o, -D, -w, -L and the URL; every other flag is ignored.
# With -L a 3xx fixture carrying a Location header is followed, as curl does: each hop is
# logged, -D gets every hop's headers in order, -w and -o get the last hop's.
# No fixture matches -> exit 7 (curl's "couldn't connect"), so a missing fixture looks like
# offline and never like success. Every call is logged to $CURL_STUB_DIR/calls.log.
: "${CURL_STUB_DIR:?CURL_STUB_DIR must point at a fixture directory}"
method="" body="" url="" out="" hdrout="" wfmt="" headers="" follow=0
while [ $# -gt 0 ]; do
  case "$1" in
    -X|--request) method="$2"; shift 2 ;;
    -d|--data|--data-raw|--data-binary) body="$2"; shift 2 ;;
    -H|--header) headers="${headers:+$headers; }$2"; shift 2 ;;
    -o|--output) out="$2"; shift 2 ;;
    -D|--dump-header) hdrout="$2"; shift 2 ;;
    -w|--write-out) wfmt="$2"; shift 2 ;;
    -L|--location) follow=1; shift ;;
    --max-redirs) shift 2 ;;
    -m|--max-time|--connect-timeout|-u|-A) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$method" ] || { [ -n "$body" ] && method=POST || method=GET; }
flat_body=$(printf '%s' "$body" | tr '\n\t' '  ')
[ -z "$hdrout" ] || : > "$hdrout"

# respond <url>: serve the first matching fixture (headers appended to -D); 1 when none matches
respond() {
  printf '%s\t%s\t%s\t%s\n' "$method" "$1" "$headers" "$flat_body" >> "$CURL_STUB_DIR/calls.log"
  for f in "$CURL_STUB_DIR"/*.http; do
    [ -f "$f" ] || continue
    first=$(head -n 1 "$f")
    case "$first" in "# match: "*) ;; *) continue ;; esac
    spec=${first#"# match: "}
    m=${spec%% *}; rest=${spec#"$m"}; rest=${rest# }
    u=${rest%% *}; b=""
    case "$rest" in *" "*) b=${rest#*" "} ;; esac
    [ "$m" = "$method" ] || continue
    printf '%s' "$1" | grep -Eq -- "$u" || continue
    if [ -n "$b" ]; then printf '%s' "$body" | grep -Eq -- "$b" || continue; fi
    status=200; hdrs=""; resp=""; inbody=0; n=0; location=""
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1)); [ "$n" -eq 1 ] && continue
      if [ "$inbody" -eq 0 ]; then
        case "$line" in
          "# status: "*) status=${line#"# status: "}; continue ;;
          "# header: "*) hdrs="${hdrs}${line#"# header: "}"$'\n'
                         case "$line" in "# header: "[Ll]ocation:*) location=${line#*: }; location=${location#*: } ;; esac
                         continue ;;
        esac
        inbody=1
      fi
      resp="${resp}${line}"$'\n'
    done < "$f"
    [ -z "$hdrout" ] || printf 'HTTP/1.1 %s\n%s\n' "$status" "$hdrs" >> "$hdrout"
    return 0
  done
  return 1
}

hops=0
while :; do
  respond "$url" || exit 7
  case "$status" in 3*) ;; *) break ;; esac
  [ "$follow" -eq 1 ] && [ -n "$location" ] || break
  hops=$((hops + 1)); [ "$hops" -le 10 ] || exit 47
  url=$location
done
if [ -n "$out" ]; then printf '%s' "$resp" > "$out"; else printf '%s' "$resp"; fi
case "$wfmt" in *'%{http_code}'*) printf '%s' "${wfmt//%\{http_code\}/$status}" ;; esac
exit 0
