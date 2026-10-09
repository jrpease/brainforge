#!/usr/bin/env bash
# Test routing/coverage.sh — the join that answers "is every doc reachable by the questions it
# answers?". Builds real brains and runs the real generator, so the manifest shape under test is
# the one gen-manifest.sh actually emits rather than a hand-written approximation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COV="$ROOT/synapse/routing/coverage.sh"
GEN="$ROOT/scaffold/.brainforge/gen-manifest.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# brain <name> -> a git repo at $TMP/<name>, cwd left inside it
brain() { mkdir -p "$TMP/$1"; cd "$TMP/$1"; git init -q; }
domain() { # domain <path> <kinds-or-empty> <title> [words]
  mkdir -p "$1"
  { echo '---'
    [ -n "$2" ] && echo "kinds: [$2]"
    echo "title: $3"
    echo '---'; } > "$1/_index.md"
  awk -v n="${4:-20}" 'BEGIN { print "# Doc"; for (i=0;i<n;i++) printf "word " }' > "$1/doc.md"
}
gen() { git add -A; git commit -q -m x; bash "$GEN" > /dev/null; }

# --- 1. a healthy brain is clean and exits 0 ---
brain healthy
domain context/canon/brand "brand-voice, naming" Brand
gen
out=$(bash "$COV" .brainforge/brain-manifest.json) || fail "clean brain must exit 0"
echo "$out" | grep -q "every domain is reachable"   || fail "clean brain must say so"
echo "$out" | grep -q "✗"                           && fail "clean brain must raise no defect"

# a brain answers only some intents; the rest are listed as informational, not as failures
echo "$out" | grep -q "intents this brain cannot answer" || fail "unanswerable intents not listed"

# --- 2. an orphan kind is a defect: named, with its domain, exit 1 ---
brain orphan
domain context/canon/mixed "brand-voice, wildly-invented" Mixed
gen
set +e; out=$(bash "$COV" .brainforge/brain-manifest.json); rc=$?; set -e
[ "$rc" -eq 1 ]                                     || fail "orphan kind must exit 1 (got $rc)"
echo "$out" | grep -q "unroutable kinds"            || fail "orphan kind not reported"
echo "$out" | grep -q "wildly-invented"             || fail "orphan kind not named"
echo "$out" | grep -q "context/canon/mixed"         || fail "orphan kind's domain not named"
echo "$out" | grep -q "brand-voice"                 && fail "in-vocabulary kind wrongly reported"
# one good kind still reaches the domain, so it is not ALSO unreachable
echo "$out" | grep -q "unreachable domains"         && fail "partially-routable domain called unreachable"

# --- 3. a domain declaring no kinds is unreachable, and says which ---
brain unclassified
domain context/derived/mystery "" Mystery
gen
set +e; out=$(bash "$COV" .brainforge/brain-manifest.json); rc=$?; set -e
[ "$rc" -eq 1 ]                                     || fail "unreachable domain must exit 1 (got $rc)"
echo "$out" | grep -q "unreachable domains"         || fail "unreachable domain not reported"
echo "$out" | grep -q "(declares none)"             || fail "must distinguish 'declares none' from dead kinds"

# --- 4. a narrow gate is a smell, not a defect: reported, but exit 0 ---
brain narrow
domain context/derived/tracker "project-tracking" Tracker 9000
gen
grep -q '"band": "expensive"' .brainforge/brain-manifest.json || fail "fixture is not expensive"
out=$(bash "$COV" .brainforge/brain-manifest.json) || fail "a narrow gate alone must NOT fail the run"
echo "$out" | grep -q "narrow gates"                || fail "narrow gate not reported"
echo "$out" | grep -q "context/derived/tracker"     || fail "narrow gate must name the domain"
echo "$out" | grep -q "planning or prioritizing work" || fail "narrow gate must name the gating intent"

# the band is what makes it narrow: the same kind in a cheap domain is not a narrow gate
brain not-narrow
domain context/derived/tracker "project-tracking" Tracker 20
gen
out=$(bash "$COV" .brainforge/brain-manifest.json)
echo "$out" | grep -q "narrow gates"                && fail "cheap domain wrongly called a narrow gate"

# a second intent on the domain clears it -- the documented fix has to actually work
brain widened
domain context/derived/tracker "project-tracking, product-roadmap, repo-summaries" Tracker 9000
gen
out=$(bash "$COV" .brainforge/brain-manifest.json)
echo "$out" | grep -q "narrow gates"                && fail "domain reached by two intents still called narrow"

# --- 4b. --narrow-paths feeds the map's line marker ---
cd "$TMP/narrow"
out=$(bash "$COV" .brainforge/brain-manifest.json --narrow-paths)
[ "$out" = "context/derived/tracker" ]              || fail "--narrow-paths must print exactly the narrow domain paths (got '$out')"
cd "$TMP/not-narrow"
out=$(bash "$COV" .brainforge/brain-manifest.json --narrow-paths)
[ -z "$out" ]                                       || fail "--narrow-paths must be empty when nothing is narrow"

# --- 4c. a map with no domains is a defect, not a pass. Every "no findings" check is
#         vacuously true on an empty set, which is how a wrong context root read as healthy. ---
brain empty
mkdir -p .brainforge
git commit -q --allow-empty -m x
printf '{\n  "schema": 3,\n  "brain": "e",\n  "remote": "",\n  "contextRoot": "context",\n  "contextFingerprint": "",\n  "generatedFrom": "x",\n  "generatedAt": "2026-01-01",\n  "domains": [\n  ],\n  "unclassified": [\n  ],\n  "unindexed": [\n  ]\n}\n' > .brainforge/brain-manifest.json
set +e; out=$(bash "$COV" .brainforge/brain-manifest.json); rc=$?; set -e
[ "$rc" -eq 1 ]                                     || fail "a zero-domain map must exit 1 (got $rc)"
echo "$out" | grep -q "no domains"                  || fail "zero-domain map must say so"
echo "$out" | grep -q "every domain is reachable"   && fail "zero-domain map must never report clean"
out=$(bash "$COV" .brainforge/brain-manifest.json --map)
echo "$out" | grep -q "NO domains"                  || fail "--map must surface a zero-domain map"

# --- 5. --map mode: the reader's warning lines only, and never a non-zero exit ---
cd "$TMP/orphan"
out=$(bash "$COV" .brainforge/brain-manifest.json --map) || fail "--map must always exit 0"
echo "$out" | grep -q 'unroutable kind "wildly-invented"' || fail "--map missing the unroutable line"
echo "$out" | grep -q "narrow gate"                 && fail "--map must not emit narrow-gate lines any more"
echo "$out" | grep -q "Routing coverage"            && fail "--map must not print the report header"
echo "$out" | grep -q "cannot answer"               && fail "--map must not print audit-only findings"

# --- 6. no manifest: quiet, and never a crash ---
cd "$TMP"
out=$(bash "$COV" "$TMP/does-not-exist.json") || fail "missing manifest must not fail"
echo "$out" | grep -q "no manifest"                 || fail "missing manifest should say so"
out=$(bash "$COV" "$TMP/does-not-exist.json" --map) || fail "missing manifest must not fail in --map"
[ -z "$out" ]                                       || fail "--map must stay silent with no manifest"

echo "PASS routing-coverage"
