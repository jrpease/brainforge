#!/usr/bin/env bash
# Test envelope-check.sh — golden rule 6 envelope and growth arithmetic, exact output bytes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="$ROOT/scaffold/.brainforge/envelope-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# A scaffold-shaped brain: the shipped adapter playbooks under pipeline/adapters/.
B="$TMP/brain"; mkdir -p "$B"; cd "$B" || exit 1; git init -q
cp -R "$ROOT/scaffold/pipeline" pipeline

M=derived/monday; G=derived/repos; A=derived/ga
# dom <path> <indexTokens> <total> <files...as "name:tokens">  -> one manifest domain object
dom() {
  local p=$1 idx=$2 tot=$3; shift 3
  local fs="" f
  for f in "$@"; do fs="$fs{ \"path\": \"${f%%:*}\", \"title\": \"t\", \"tokens\": ${f##*:} },"; done
  printf '{ "path": "context/%s", "kinds": [], "tokens": %s, "indexTokens": %s, "files": [%s] }' \
    "$p" "$tot" "$idx" "${fs%,}"
}
# manifest <file> <schema> <domain objects...>
manifest() {
  local f=$1 s=$2; shift 2
  local IFS=,
  printf '{ "schema": %s, "domains": [%s] }\n' "$s" "$*" > "$f"
}
# sources <json arrays body>, e.g. '"monday": [ ... ]'
sources() { printf '{ "version": 1, "$examples": { "monday": { "id": "ex", "into": "context/x/" } }, %s }\n' "$1" > sources.json; }
src() { printf '{ "id": "%s", "into": "context/%s/", "enabled": true %s }' "$1" "$2" "${3:-}"; }

run() { out=$(bash "$EC" "$@"); rc=$?; }
expect() { # <label> <expected stdout>
  [ "$rc" -eq 0 ] || fail "$1: exit $rc (out: $out)"
  [ "$out" = "$2" ] || fail "$1: expected
[$2]
got
[$out]"
}

: > prev-empty.json
sources "\"monday\": [$(src roadmap $M)], \"repos\": [$(src web $G ', "acceptedSize": [{ "doc": "web.md", "tokens": 6000, "since": "2026-10-07", "why": "test" }]')], \"ga\": [$(src analytics $A)]"

# (a) a doc over its adapter row (<board>.md wildcard, 3,000) -> the per-doc line, exact bytes
manifest cur.json 3 "$(dom $M 500 4000 roadmap.md:3500)"
run prev-empty.json cur.json sources.json roadmap
expect "(a) over envelope" "⚠ rule-6: context/derived/monday/roadmap.md is 3500 tokens (envelope 3000 / was n/a) — consider aggregating."

# (b) under the envelope but >= 3x prev -> the line with was <P>
manifest prev.json 3 "$(dom $M 500 1000 roadmap.md:500)"
manifest cur.json 3 "$(dom $M 500 2000 roadmap.md:1500)"
run prev.json cur.json sources.json roadmap
expect "(b) growth" "⚠ rule-6: context/derived/monday/roadmap.md is 1500 tokens (envelope 3000 / was 500) — consider aggregating."
manifest cur.json 3 "$(dom $M 500 1999 roadmap.md:1499)"
run prev.json cur.json sources.json roadmap
expect "(b) just under 3x is silent" ""

# (c) acceptedSize covers it -> silent; the same doc tripled -> the line (growth applies to accepted docs)
manifest prev.json 3 "$(dom $G 500 4500 web.md:4000)"
manifest cur.json 3 "$(dom $G 500 5500 web.md:5000)"
run prev.json cur.json sources.json web
expect "(c) accepted is silent" ""
manifest prev.json 3 "$(dom $G 500 2000 web.md:1500)"
run prev.json cur.json sources.json web
expect "(c) accepted but tripled" "⚠ rule-6: context/derived/repos/web.md is 5000 tokens (envelope 6000 / was 1500) — consider aggregating."

# (d) _index.md checked via indexTokens; a schema-1 prev gives no baseline -> was n/a
manifest prev.json 1 "$(dom $M 100 600 roadmap.md:500)"
manifest cur.json 3 "$(dom $M 2000 2500 roadmap.md:500)"
run prev.json cur.json sources.json roadmap
expect "(d) index, schema-1 prev" "⚠ rule-6: context/derived/monday/_index.md is 2000 tokens (envelope 1500 / was n/a) — consider aggregating."
manifest prev.json 2 "$(dom $M 100 600 roadmap.md:500)"
manifest cur.json 3 "$(dom $M 400 900 roadmap.md:500)"
run prev.json cur.json sources.json roadmap
expect "(d) index, schema-2 prev is a baseline" "⚠ rule-6: context/derived/monday/_index.md is 400 tokens (envelope 1500 / was 100) — consider aggregating."

# (e) domain total over while every doc is under -> the domain line only
manifest cur.json 3 "$(dom $M 1000 5000 board-a.md:2000 board-b.md:2000)"
run prev-empty.json cur.json sources.json roadmap
expect "(e) domain total" "⚠ rule-6: context/derived/monday totals 5000 tokens (envelope 4500) — consider aggregating."

# (f) no adapter row (ga has no wildcard) -> the 8,000 default
manifest cur.json 3 "$(dom $A 100 4100 notes.md:4000)"
run prev-empty.json cur.json sources.json analytics
expect "(f) under default" ""
manifest cur.json 3 "$(dom $A 100 8101 notes.md:8001)"
run prev-empty.json cur.json sources.json analytics
expect "(f) over default" "⚠ rule-6: context/derived/ga/notes.md is 8001 tokens (envelope 8000 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/ga totals 8101 tokens (envelope 5000) — consider aggregating."

# (g) a garbled table -> the unreadable line, then the default for every doc and no domain check
cp pipeline/adapters/monday.md "$TMP/monday.md.orig"
sed 's/| ≤ 3,000 each |/| about three thousand |/' "$TMP/monday.md.orig" > pipeline/adapters/monday.md
cmp -s pipeline/adapters/monday.md "$TMP/monday.md.orig" && fail "(g) setup: sed did not garble the table"
manifest cur.json 3 "$(dom $M 2000 9000 roadmap.md:7000)"
run prev-empty.json cur.json sources.json roadmap
expect "(g) garbled table" "⚠ rule-6: monday envelope table unreadable — used the 8,000 default"
cp "$TMP/monday.md.orig" pipeline/adapters/monday.md

# (g2) a built-in adapter's playbook missing -> the unreadable line too, never a silent default
mv pipeline/adapters/monday.md "$TMP/monday.md.moved"
run prev-empty.json cur.json sources.json roadmap
expect "(g2) missing built-in table" "⚠ rule-6: monday envelope table unreadable — used the 8,000 default"
mv "$TMP/monday.md.moved" pipeline/adapters/monday.md
# ...but a custom adapter with no playbook file gets the default silently
cp sources.json "$TMP/sources.json.orig"
sources "\"notion\": [$(src wiki derived/wiki)]"
manifest cur.json 3 "$(dom derived/wiki 500 8500 page.md:8000)"
run prev-empty.json cur.json sources.json wiki
expect "(g2) custom adapter, no file, at default" ""
manifest cur.json 3 "$(dom derived/wiki 500 8501 page.md:8001)"
run prev-empty.json cur.json sources.json wiki
expect "(g2) custom adapter, no file, over default" "⚠ rule-6: context/derived/wiki/page.md is 8001 tokens (envelope 8000 / was n/a) — consider aggregating."
cp "$TMP/sources.json.orig" sources.json

# (g3) a brain inside a larger git repo: tables come from the brain root, not the git toplevel
OUTER="$TMP/outer"; mkdir -p "$OUTER"; git -C "$OUTER" init -q
cp -R "$B" "$OUTER/brain"; rm -rf "$OUTER/brain/.git"
manifest "$OUTER/brain/cur.json" 3 "$(dom $M 500 4000 roadmap.md:3500)"
out=$(cd "$OUTER/brain" && bash "$EC" prev-empty.json cur.json sources.json roadmap); rc=$?
expect "(g3) nested brain" "⚠ rule-6: context/derived/monday/roadmap.md is 3500 tokens (envelope 3000 / was n/a) — consider aggregating."

# (h) a missing prev file -> envelope-only
manifest cur.json 3 "$(dom $M 500 2500 roadmap.md:2000)"
run "$TMP/no-such-prev.json" cur.json sources.json roadmap
expect "(h) missing prev, under" ""
manifest cur.json 3 "$(dom $M 500 4000 roadmap.md:3500)"
run "$TMP/no-such-prev.json" cur.json sources.json roadmap
expect "(h) missing prev, over" "⚠ rule-6: context/derived/monday/roadmap.md is 3500 tokens (envelope 3000 / was n/a) — consider aggregating."

# (i) clean, all enabled sources (no ids) -> empty stdout, exit 0
manifest prev.json 3 "$(dom $M 500 1500 roadmap.md:1000)" "$(dom $G 500 2500 web.md:2000)"
manifest cur.json 3 "$(dom $M 500 1600 roadmap.md:1100)" "$(dom $G 500 2600 web.md:2100)" "$(dom $A 100 1100 traffic-overview.md:1000)"
run prev.json cur.json sources.json
expect "(i) clean" ""

# no ids checks every enabled source, and skips a disabled one
sources "\"monday\": [$(src roadmap $M), $(src old derived/old ', "enabled": false')]"
manifest cur.json 3 "$(dom $M 500 4000 roadmap.md:3500)" "$(dom derived/old 500 9500 x.md:9000)"
run prev-empty.json cur.json sources.json
expect "no ids: enabled only" "⚠ rule-6: context/derived/monday/roadmap.md is 3500 tokens (envelope 3000 / was n/a) — consider aggregating."

# misuse exits 1 with a message on stderr
bash "$EC" prev.json cur.json > /dev/null 2>&1 && fail "two args must exit 1"
bash "$EC" prev.json cur.json sources.json nope > /dev/null 2>&1 && fail "unknown id must exit 1"
echo '{ not json' > bad.json
bash "$EC" prev.json bad.json sources.json > /dev/null 2>&1 && fail "unreadable manifest must exit 1"
bash "$EC" prev.json "$TMP/none.json" sources.json > /dev/null 2>&1 && fail "missing manifest must exit 1"

# Every shipped adapter table parses: no "unreadable" line, and each row's own number is the one
# applied (an _index.md over every row, a figma exact row with trailing text, website's
# per-page wildcard, figma's "per-domain total ... each").
sources "\"figma\": [$(src ds derived/design-system)], \"repos\": [$(src web $G)], \"websites\": [$(src site derived/web)], \"monday\": [$(src roadmap $M)], \"ga\": [$(src analytics $A)]"
manifest cur.json 3 \
  "$(dom derived/design-system 9000 9000 figma-library.md:2600)" \
  "$(dom $G 9000 9000)" "$(dom derived/web 9000 9000 page.md:801)" \
  "$(dom $M 9000 9000)" "$(dom $A 9000 9000)"
run prev-empty.json cur.json sources.json
expect "shipped tables" "⚠ rule-6: context/derived/design-system/_index.md is 9000 tokens (envelope 2000 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/design-system/figma-library.md is 2600 tokens (envelope 2500 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/design-system totals 9000 tokens (envelope 5000) — consider aggregating.
⚠ rule-6: context/derived/repos/_index.md is 9000 tokens (envelope 1500 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/repos totals 9000 tokens (envelope 8000) — consider aggregating.
⚠ rule-6: context/derived/web/_index.md is 9000 tokens (envelope 800 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/web/page.md is 801 tokens (envelope 800 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/web totals 9000 tokens (envelope 3000) — consider aggregating.
⚠ rule-6: context/derived/monday/_index.md is 9000 tokens (envelope 1500 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/monday totals 9000 tokens (envelope 4500) — consider aggregating.
⚠ rule-6: context/derived/ga/_index.md is 9000 tokens (envelope 1000 / was n/a) — consider aggregating.
⚠ rule-6: context/derived/ga totals 9000 tokens (envelope 5000) — consider aggregating."
for a in "$ROOT"/scaffold/pipeline/adapters/*.md; do
  case "$(basename "$a")" in figma.md|github.md|website.md|monday.md|ga.md) ;; *) fail "new shipped adapter $(basename "$a") is not covered by the parse test" ;; esac
done

echo "PASS envelope-check"
