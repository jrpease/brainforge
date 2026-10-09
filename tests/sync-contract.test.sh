#!/usr/bin/env bash
# Test sync-contract.sh — adapters honour a source entry's `into:` and never write `kinds:`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/scaffold/.brainforge/sync-contract.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# brain <dir>: a git repo holding the shipped playbooks; sources <entries> writes its sources.json
brain() {
  rm -rf "$1"; mkdir -p "$1"; cd "$1"; git init -q
  cp -R "$ROOT/scaffold/pipeline" pipeline
}
sources() { printf '{ "version": 1, "$examples": { "repos": { "id": "x" } }, "repos": [%s], "figma": [] }\n' "$1" > sources.json; }

# --- 1. the shipped scaffold itself holds the contract ---
brain "$TMP/shipped"; cp "$ROOT/scaffold/sources.json" .
out=$(bash "$SC") || fail "shipped scaffold must pass (got: $out)"
echo "$out" | grep -q "sync contract holds"             || fail "clean brain must say so"
[ "$(ls pipeline/adapters/*.md pipeline/examples/*.md | wc -l)" -ge 6 ] || fail "expected the 5 adapters + shopify example"

# --- 2. the consumer case: an entry repointed to a new domain passes ---
brain "$TMP/moved"
sources '{ "id": "unit-a", "into": "context/derived/units/" }, { "id": "web", "into": "context/derived/repos/" }'
bash "$SC" > /dev/null                                  || fail "a repointed into: is valid"

# --- 3. no into: fails closed, and names the entry ---
brain "$TMP/missing"
sources '{ "id": "unit-a" }, { "id": "web", "into": "context/derived/repos/" }'
out=$(bash "$SC") && fail "an entry with no into: must exit 1"
echo "$out" | grep -q "repos\[unit-a\]: no into:"       || fail "must name the entry missing into: (got: $out)"
echo "$out" | grep -q "repos\[web\]"                    && fail "a valid entry must not be reported"
sources '{ "id": "blank", "into": "" }'
bash "$SC" > /dev/null                                  && fail "an empty into: must exit 1"

# --- 4. into: outside the derived root fails ---
for bad in "context/canon/brand/" "context/derived/" "context/derived/../canon/" "elsewhere/" "context/derived/repos"; do
  sources "{ \"id\": \"b\", \"into\": \"$bad\" }"
  bash "$SC" > /dev/null                                && fail "into: $bad must exit 1"
done

# --- 4b. a disabled entry is skipped; enabling it brings it back under the check ---
sources '{ "id": "stub", "enabled": false }'
bash "$SC" > /dev/null                                  || fail "a disabled entry with no into: must not block syncs"
sources '{ "id": "stub", "enabled": true }'
bash "$SC" > /dev/null                                  && fail "an enabled entry with no into: must exit 1"

# --- 5. the derived root follows the manifest's contextRoot ---
mkdir -p .brainforge; echo '{ "contextRoot": "docs" }' > .brainforge/brain-manifest.json
sources '{ "id": "b", "into": "docs/derived/repos/" }'
bash "$SC" > /dev/null                                  || fail "into: under a manifest contextRoot is valid"
sources '{ "id": "b", "into": "context/derived/repos/" }'
bash "$SC" > /dev/null                                  && fail "into: outside the manifest contextRoot must exit 1"

# --- 6. a playbook that hardcodes a destination fails, and names the line ---
brain "$TMP/hardcoded"
sources '{ "id": "web", "into": "context/derived/repos/" }'
echo '- Write to `context/derived/repos/<repo-name>.md`.' >> pipeline/adapters/github.md
out=$(bash "$SC") && fail "a hardcoded destination must exit 1"
echo "$out" | grep -q "pipeline/adapters/github.md:[0-9]*: hardcoded destination" || fail "must name file:line (got: $out)"

# --- 7. a playbook that stamps kinds fails ---
brain "$TMP/stamps"
sources '{ "id": "web", "into": "context/derived/repos/" }'
echo '- The emitted `_index.md` frontmatter MUST include `kinds: [repo-summaries]`.' >> pipeline/adapters/github.md
out=$(bash "$SC") && fail "a kinds stamp must exit 1"
echo "$out" | grep -q "writes kinds:"                   || fail "must report the kinds stamp (got: $out)"

# --- 7b. block-form and bare kinds are stamps too; prose about `kinds:` is not ---
for form in 'kinds:' 'kinds: repo-summaries' '  kinds: ["repo-summaries"]'; do
  brain "$TMP/stamps-form"
  sources '{ "id": "web", "into": "context/derived/repos/" }'
  printf '%s\n' "$form" >> pipeline/adapters/github.md
  bash "$SC" > /dev/null                                && fail "kinds stamp form not caught: $form"
done
brain "$TMP/stamps-prose"
sources '{ "id": "web", "into": "context/derived/repos/" }'
echo '- Never write `kinds:` in the index.' >> pipeline/adapters/github.md
bash "$SC" > /dev/null                                  || fail "prose naming \`kinds:\` must not be a stamp"

# --- 8. a custom adapter that never mentions into fails ---
brain "$TMP/custom"
sources '{ "id": "web", "into": "context/derived/repos/" }'
printf '# Playbook: sync Notion\n\nCount pages into a total and write them to the notion folder.\n' > pipeline/adapters/notion.md
out=$(bash "$SC") && fail "a playbook that never mentions into must exit 1"
echo "$out" | grep -q "notion.md: never mentions into" || fail "must name the playbook (got: $out)"

# --- 9. an unparseable sources.json fails closed ---
brain "$TMP/broken"; echo '{ "repos": [ ' > sources.json
bash "$SC" > /dev/null                                  && fail "unparseable sources.json must exit 1"

# --- 10. wiring: /sync and sync-all run it first, and the upgrade seam carries it ---
grep -q 'bash .brainforge/sync-contract.sh' "$ROOT/scaffold/.claude/commands/sync.md" || fail "/sync does not run the contract"
grep -q 'bash .brainforge/sync-contract.sh' "$ROOT/scaffold/pipeline/sync-all.md"      || fail "sync-all does not run the contract"
grep -q '".brainforge/sync-contract.sh"' "$ROOT/.claude-plugin/plugin.json"             || fail "sync-contract.sh is not in runtime.bump"

echo "PASS sync-contract"
