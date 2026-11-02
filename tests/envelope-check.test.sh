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
# (c3) one entry's domain-total acceptance covers every entry feeding that domain
sources "\"monday\": [$(src roadmap $M ', "acceptedSize": [{ "doc": "domain total", "tokens": 6000, "since": "2026-10-13", "why": "test" }]'), $(src roadmap2 $M)]"
manifest cur.json 3 "$(dom $M 500 5500 roadmap.md:2000)"
run prev-empty.json cur.json sources.json roadmap2
expect "(c3) acceptance on a sibling entry covers the domain" ""
run prev-empty.json cur.json sources.json
expect "(c3) bare run, every entry covered" ""
# (c4) the latest acceptance wins by `since`, not by position (the newer one is listed first)
sources "\"monday\": [$(src roadmap $M ', "acceptedSize": [{ "doc": "domain total", "tokens": 5000, "since": "2026-10-13", "why": "new" }]'), $(src roadmap2 $M ', "acceptedSize": [{ "doc": "domain total", "tokens": 7000, "since": "2026-09-01", "why": "old" }]')]"
run prev-empty.json cur.json sources.json
expect "(c4) latest acceptance wins" "⚠ rule-6: context/derived/monday totals 5500 tokens (envelope 5000) — consider aggregating."
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

# (c2) an accepted "domain total" replaces the table total for the domain; over it still warns
sources "\"monday\": [$(src roadmap $M ', "acceptedSize": [{ "doc": "domain total", "tokens": 6000, "since": "2026-10-13", "why": "test" }]')]"
manifest prev.json 3 "$(dom $M 500 5500 roadmap.md:2000)"
manifest cur.json 3 "$(dom $M 500 5500 roadmap.md:2000)"
run prev.json cur.json sources.json roadmap
expect "(c2) accepted domain total is silent" ""
manifest cur.json 3 "$(dom $M 500 6500 roadmap.md:2000)"
run prev.json cur.json sources.json roadmap
expect "(c2) over the accepted total" "⚠ rule-6: context/derived/monday totals 6500 tokens (envelope 6000) — consider aggregating."
sources "\"monday\": [$(src roadmap $M)], \"repos\": [$(src web $G ', "acceptedSize": [{ "doc": "web.md", "tokens": 6000, "since": "2026-10-07", "why": "test" }]')], \"ga\": [$(src analytics $A)]"

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

# (w) several wildcard rows: each is a glob, the most specific match wins whatever the row order,
# an exact row still beats them all, and a doc that no glob matches gets the default.
cat > pipeline/adapters/linear.md <<'EOF'
## 0a. Size envelope

| Emitted doc | Envelope |
|---|---|
| `<doc>.md` | ≤ 3,000 each |
| `issues-<team>.md` | ≤ 1,500 each |
| `<team>-cycle-<n>.md` | ≤ 900 each |
| `_index.md` | ≤ 500 |
| **domain total** | **≤ 90,000** |
EOF
L=derived/linear
sources "\"linear\": [$(src tracker $L)]"
manifest cur.json 3 "$(dom $L 500 5000 issues-core.md:1500 core-cycle-12.md:900 notes.md:3000 data.json:8000)"
run prev-empty.json cur.json sources.json tracker
expect "(w) every doc at its own envelope" ""
manifest cur.json 3 "$(dom $L 501 5000 issues-core.md:1501 core-cycle-12.md:901 notes.md:3001 data.json:8001)"
run prev-empty.json cur.json sources.json tracker
expect "(w) every doc over its own envelope" "⚠ rule-6: context/$L/_index.md is 501 tokens (envelope 500 / was n/a) — consider aggregating.
⚠ rule-6: context/$L/issues-core.md is 1501 tokens (envelope 1500 / was n/a) — consider aggregating.
⚠ rule-6: context/$L/core-cycle-12.md is 901 tokens (envelope 900 / was n/a) — consider aggregating.
⚠ rule-6: context/$L/notes.md is 3001 tokens (envelope 3000 / was n/a) — consider aggregating.
⚠ rule-6: context/$L/data.json is 8001 tokens (envelope 8000 / was n/a) — consider aggregating."
# (w1) the rows that broke a real brain: trailing text in the cell, a backtick inside it, a compound row
cat > pipeline/adapters/linear.md <<'EOF'
## 0a. Size envelope

| Emitted doc | Envelope |
|---|---|
| `<view-id>.md` (a `view`) | ≤ 7,000 |
| `<pattern-id>-<slug>.md` (each `view-pattern` match) | ≤ 1,500 |
EOF
manifest cur.json 3 "$(dom $L 100 9000 roadmap.md:7000 bug-login.md:1501)"
run prev-empty.json cur.json sources.json tracker
expect "(w1) the compound row is enforced" "⚠ rule-6: context/$L/bug-login.md is 1501 tokens (envelope 1500 / was n/a) — consider aggregating."
# (w2) a genuinely malformed first cell still fails the whole table
for bad in '`issues-<>.md`' '`issues-<team.md`' 'issues-<team>.md'; do
  printf '## 0a. Size envelope\n\n| Emitted doc | Envelope |\n|---|---|\n| %s | ≤ 1,500 |\n' "$bad" > pipeline/adapters/linear.md
  run prev-empty.json cur.json sources.json tracker
  case "$out" in "⚠ rule-6: linear envelope table unreadable — used the 8,000 default"*) ;; *) fail "(w2) $bad must fail the table, got [$out]" ;; esac
done
rm pipeline/adapters/linear.md

# (s) two adapters share one domain: figma (exact rows only, total 5,000), github (<repo-name>.md 2,500, total 8,000)
S=derived/shared; mkdir -p "context/$S"
stamp() { printf -- '---\n%s\n---\nbody\n' "$2" > "context/$S/$1"; }
stamp lib.md 'generated-by: pipeline/adapters/figma.md (REST)'
stamp old.md 'generated-by: figma-adapter'
stamp web.md 'generated-by: pipeline/adapters/github.md'
stamp repo.md 'source: "Repo · org/x @ abc123"'
stamp both.md 'generated-by: pipeline/adapters/figma.md + pipeline/adapters/github.md'
stamp other.md 'generated-by: pipeline/adapters/shopify.md'
sources "\"figma\": [$(src ds $S)], \"repos\": [$(src code $S)]"
# (s1) a doc goes against its emitter only; one naming no feeder takes the most specific row
manifest cur.json 3 "$(dom $S 100 4000 lib.md:3000 old.md:3000 web.md:2500 repo.md:2500 both.md:2500 other.md:2500)"
run prev-empty.json cur.json sources.json
expect "(s1) every doc at its emitter's envelope" ""
manifest cur.json 3 "$(dom $S 100 4000 lib.md:8001 web.md:2501 repo.md:2501 both.md:2501 other.md:2501)"
run prev-empty.json cur.json sources.json
expect "(s1) over the emitter's envelope, one line each" "⚠ rule-6: context/$S/lib.md is 8001 tokens (envelope 8000 / was n/a) — consider aggregating.
⚠ rule-6: context/$S/web.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating.
⚠ rule-6: context/$S/repo.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating.
⚠ rule-6: context/$S/both.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating.
⚠ rule-6: context/$S/other.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating."
# (s2) an exact row beats a wildcard from the other adapter; a shared _index.md takes the larger exact row
# (figma's exact figma-library.md is 2,500; monday's <board>.md wildcard is 3,000, so these numbers tell them apart)
sources "\"figma\": [$(src ds $S)], \"monday\": [$(src board $S)]"
manifest cur.json 3 "$(dom $S 2001 4000 figma-library.md:2501)"
run prev-empty.json cur.json sources.json
expect "(s2) exact rows across adapters" "⚠ rule-6: context/$S/_index.md is 2001 tokens (envelope 2000 / was n/a) — consider aggregating.
⚠ rule-6: context/$S/figma-library.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating."
sources "\"figma\": [$(src ds $S)], \"repos\": [$(src code $S)]"
# (s3) the domain total prints once, against the largest, whichever entry is named
manifest cur.json 3 "$(dom $S 100 8001)"
for ids in "" ds code; do
  run prev-empty.json cur.json sources.json $ids
  expect "(s3) one total [$ids]" "⚠ rule-6: context/$S totals 8001 tokens (envelope 8000) — consider aggregating."
done
# (s4) a per-doc acceptance on either entry covers the doc, whichever entry is being checked
sources "\"figma\": [$(src ds $S ', "acceptedSize": [{ "doc": "web.md", "tokens": 6000, "since": "2026-10-30", "why": "test" }]')], \"repos\": [$(src code $S)]"
manifest cur.json 3 "$(dom $S 100 7000 web.md:6000)"
for ids in "" ds code; do
  run prev-empty.json cur.json sources.json $ids
  expect "(s4) accepted on a sibling [$ids]" ""
done
# (s5) the latest per-doc acceptance wins by `since`, not by position
sources "\"figma\": [$(src ds $S ', "acceptedSize": [{ "doc": "web.md", "tokens": 5000, "since": "2026-10-30", "why": "new" }]')], \"repos\": [$(src code $S ', "acceptedSize": [{ "doc": "web.md", "tokens": 7000, "since": "2026-09-01", "why": "old" }]')]"
run prev-empty.json cur.json sources.json
expect "(s5) latest per-doc acceptance wins" "⚠ rule-6: context/$S/web.md is 6000 tokens (envelope 5000 / was n/a) — consider aggregating."
# (s5a) a disabled entry sharing the folder cannot raise the envelope, and its table goes unread;
# its acceptance still counts. Naming it brings its table back in.
sources "\"monday\": [$(src board $S)], \"repos\": [$(src code $S ', "enabled": false')]"
manifest cur.json 3 "$(dom $S 100 5000 web.md:3001)"
run prev-empty.json cur.json sources.json
expect "(s5a) disabled entry ignored" "⚠ rule-6: context/$S/web.md is 3001 tokens (envelope 3000 / was n/a) — consider aggregating.
⚠ rule-6: context/$S totals 5000 tokens (envelope 4500) — consider aggregating."
run prev-empty.json cur.json sources.json code
expect "(s5a) disabled entry named" "⚠ rule-6: context/$S/web.md is 3001 tokens (envelope 2500 / was n/a) — consider aggregating."
sources "\"monday\": [$(src board $S)], \"repos\": [$(src code $S ', "enabled": false, "acceptedSize": [{ "doc": "web.md", "tokens": 3500, "since": "2026-10-30", "why": "test" }]')]"
run prev-empty.json cur.json sources.json
expect "(s5a) disabled entry's acceptance counts" "⚠ rule-6: context/$S totals 5000 tokens (envelope 4500) — consider aggregating."
# (s6) with one feeder the frontmatter is not consulted: the only adapter's table applies
sources "\"repos\": [$(src code $S)]"
manifest cur.json 3 "$(dom $S 100 4000 lib.md:2501)"
run prev-empty.json cur.json sources.json
expect "(s6) a lone adapter measures every doc" "⚠ rule-6: context/$S/lib.md is 2501 tokens (envelope 2500 / was n/a) — consider aggregating."

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
