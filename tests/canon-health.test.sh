#!/usr/bin/env bash
# Test canon-health.sh — the staleness signal for authored canon, and its session-start wiring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CH="$ROOT/scaffold/.brainforge/canon-health.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ago() { date -v-"$1"d +%F 2>/dev/null || date -d "$1 days ago" +%F; }

# doc <path> <owner> <last-reviewed> <status> [review-cadence]
doc() {
  mkdir -p "$(dirname "$1")"
  { echo '---'; echo "title: T"; echo "owner: $2"; echo "last-reviewed: $3"; echo "status: $4"
    [ -n "${5:-}" ] && echo "review-cadence: $5"; echo '---'; echo; echo "# T"; echo body; } > "$1"
}

# --- a brain whose canon is all current: silent tripwire, clean report, exit 0 ---
B="$TMP/clean"; mkdir -p "$B"; cd "$B"; git init -q
doc context/canon/brand/voice.md Jordan "$(ago 5)" approved
git add -A; git commit -q -m c
out=$(bash "$CH") || fail "a current brain must exit 0"
echo "$out" | grep -q "every approved canon doc is within" || fail "clean brain must say so"
out=$(bash "$CH" --tripwire) || fail "tripwire must exit 0"
[ -z "$out" ]                                       || fail "tripwire must be SILENT on a healthy brain (got: $out)"

# --- the four states, on one brain ---
B="$TMP/mixed"; mkdir -p "$B"; cd "$B"; git init -q
doc context/canon/brand/voice.md      Jordan "$(ago 400)" approved            # past review, default
doc context/canon/brand/messaging.md  Priya  "$(ago 5)"   approved            # current
doc context/canon/brand/naming.md     TODO   TODO         approved            # NEVER reviewed
doc context/canon/product/tenets.md   Sam    "$(ago 4000)" approved never     # opt-out
doc context/canon/product/roadmap.md  Sam    "$(ago 100)" approved quarterly  # past a tighter cadence
doc context/canon/brand/arch.md       TODO   TODO         draft               # stalled draft
GIT_COMMITTER_DATE="$(ago 200)T00:00:00" git add -A
GIT_COMMITTER_DATE="$(ago 200)T00:00:00" git commit -q -m c
doc context/canon/brand/fresh.md      TODO   TODO         draft               # fresh draft
git add -A; git commit -q -m f

set +e; out=$(bash "$CH"); rc=$?; set -e
[ "$rc" -eq 1 ]                                     || fail "stale canon must exit 1 (got $rc)"
echo "$out" | grep -q "never reviewed"              || fail "never-reviewed section missing"
echo "$out" | grep -q "brand/naming.md"             || fail "never-reviewed doc not named"
echo "$out" | grep -q "brand/voice.md"              || fail "past-review doc not named"
echo "$out" | grep -q "biannual (default)"          || fail "must say which cadence was applied"
echo "$out" | grep -q "product/roadmap.md"          || fail "quarterly override not enforced"
echo "$out" | grep -q "quarterly"                   || fail "quarterly label missing"
# the opt-out is honoured: 4000 days stale, declared never, must not appear as a finding
echo "$out" | grep -q "product/tenets.md"           && fail "review-cadence: never was not honoured"
echo "$out" | grep -q "brand/messaging.md"          && fail "a current doc was reported"
echo "$out" | grep -q "owner: Jordan"               || fail "owner not surfaced for accountability"
# drafts are a SEPARATE finding, and staleness of an unapproved doc is not the same question
echo "$out" | grep -q "brand/arch.md"               || fail "stalled draft not reported"
echo "$out" | grep -qE "arch\.md.*stalled"          || fail "stalled draft not marked stalled"
echo "$out" | grep -qE "fresh\.md.*open"            || fail "a fresh draft must not be called stalled"

# --- the tripwire is ONE line, never one per doc, and never fails ---
out=$(bash "$CH" --tripwire) || fail "tripwire must always exit 0, even with findings"
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ]     || fail "tripwire must print exactly one line"
echo "$out" | grep -q "never reviewed"              || fail "tripwire must name the worst state"
echo "$out" | grep -q "/canon-health"               || fail "tripwire must name the command that explains it"
echo "$out" | grep -q "voice.md"                    && fail "tripwire must not enumerate docs"

# --- a non-default context root is honoured, not assumed ---
B="$TMP/rooted"; mkdir -p "$B"; cd "$B"; git init -q
mkdir -p .brainforge
doc docs/canon/brand/voice.md Jordan "$(ago 400)" approved
printf '{\n  "schema": 3,\n  "contextRoot": "docs",\n}\n' > .brainforge/brain-manifest.json
git add -A; git commit -q -m c
set +e; out=$(bash "$CH"); rc=$?; set -e
[ "$rc" -eq 1 ]                                     || fail "must find canon under a non-default root"
echo "$out" | grep -q "docs/canon"                  || fail "contextRoot from the manifest not used"

# --- no canon at all: silent, never an error ---
B="$TMP/nocanon"; mkdir -p "$B"; cd "$B"; git init -q
git commit -q --allow-empty -m e
out=$(bash "$CH") || fail "a brain with no canon must not fail"
[ -z "$out" ]                                       || fail "no canon should be silent (got: $out)"

# --- the wiring: run the ACTUAL session-start.sh the scaffold ships ---
SS="$ROOT/scaffold/.brainforge/session-start.sh"
[ "$(grep -c 'canon-health.sh --tripwire' "$SS")" -eq 1 ] || fail "expected exactly one canon-health hook in session-start.sh"
mkdir -p "$TMP/mixed/.brainforge"; cp "$CH" "$TMP/mixed/.brainforge/canon-health.sh"
chmod +x "$TMP/mixed/.brainforge/canon-health.sh"
out=$(CLAUDE_PROJECT_DIR="$TMP/mixed" bash "$SS") || fail "session-start.sh must exit 0"
echo "$out" | grep -q "Canon health"                || fail "session-start.sh produced no canon nudge"
# and it must stay silent, not error, on a brain that has not upgraded (no script present)
out=$(CLAUDE_PROJECT_DIR="$TMP/nocanon" bash "$SS") || fail "session-start.sh must not fail when canon-health.sh is absent"
echo "$out" | grep -q "Canon health"                && fail "no canon nudge when canon-health.sh is absent"

echo "PASS canon-health"
