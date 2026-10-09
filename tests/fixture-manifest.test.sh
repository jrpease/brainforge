#!/usr/bin/env bash
# Test that the eval fixture's committed manifest is exactly what gen-manifest.sh emits for it.
# The routing evals read this file directly, so a stale one tests a map no brain produces.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$ROOT/scaffold/.brainforge/gen-manifest.sh"
FIX="$ROOT/evals/fixtures/acme-brain"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Named acme-brain so the generator's `brain` (the dir basename when there is no remote) matches.
B="$TMP/acme-brain"; mkdir -p "$B"; cd "$B"; git init -q
cp -R "$FIX/context" .
bash "$GEN" > /dev/null || fail "generator exited non-zero on the fixture"

# These lines depend on the temp repo and the day, not on the fixture's content.
strip() { grep -vE '^  "(remote|generatedFrom|generatedAt|contextFingerprint)": ' "$1"; }
strip .brainforge/brain-manifest.json > "$TMP/fresh"
strip "$FIX/.brainforge/brain-manifest.json" > "$TMP/committed"
diff -u "$TMP/committed" "$TMP/fresh" \
  || fail "evals/fixtures/acme-brain/.brainforge/brain-manifest.json is out of date; regenerate it"

echo "PASS fixture-manifest"
