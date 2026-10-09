#!/usr/bin/env bash
# Test gen-manifest.sh against a synthetic brain in a temp dir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$ROOT/scaffold/.brainforge/gen-manifest.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# --- fixture brain ---
cd "$TMP"; git init -q; git commit -q --allow-empty -m init
mkdir -p context/canon/brand context/derived/tracker context/special/quoted
cat > context/canon/brand/_index.md <<'EOF'
---
kinds: [brand-voice, naming]
title: Brand
---
| doc | what |
EOF
cat > context/canon/brand/voice.md <<'EOF'
# Voice & tone
We speak plainly. Ten more words of voice guidance land here now.
EOF
cat > context/derived/tracker/_index.md <<'EOF'
---
title: Tracker
---
EOF
# big file: 9000 words -> 12000 tokens -> expensive
awk 'BEGIN { for (i=0;i<9000;i++) printf "word " }' > context/derived/tracker/big.md
# domain with quoted title and file with quoted heading
cat > context/special/quoted/_index.md <<'EOF'
---
kinds: [edge-case]
title: The "Weird" Domain
---
EOF
cat > context/special/quoted/edge.md <<'EOF'
# Escaping "Quotes" Works
Some content here about edge cases.
EOF
# domain whose title contains a backslash: escape_json doubles it, printf '%b' used to eat it
mkdir -p context/special/back
cat > context/special/back/_index.md <<'EOF'
---
kinds: [edge-case]
title: Back\slash "and quote"
---
EOF
cat > context/special/back/doc.md <<'EOF'
# Doc
Some content here about backslashes.
EOF
# schema 2 fixture: docTokens alone would band this "cheap"; _index.md + .json push it to "normal"
mkdir -p context/derived/budget
{ echo '---'; echo 'kinds: [project-tracking]'; echo 'title: Budget'; echo '---';
  awk 'BEGIN { for (i=0;i<1400;i++) printf "index " }'; } > context/derived/budget/_index.md
{ echo '# Small doc'; awk 'BEGIN { for (i=0;i<900;i++) printf "word " }'; } > context/derived/budget/small.md
awk 'BEGIN { printf "{"; for (i=0;i<300;i++) printf "\"k%d\": \"v\", ", i; printf "\"last\": 1 }" }' \
  > context/derived/budget/data.json

git add -A; git commit -q -m fixture

# --- run ---
bash "$GEN" || fail "generator exited non-zero"
M=.brainforge/brain-manifest.json
[ -f "$M" ] || fail "manifest not written"

# --- assertions ---
python3 -m json.tool "$M" > /dev/null || fail "manifest is not valid JSON"
grep -q '"generatedFrom": "'"$(git rev-parse HEAD)"'"' "$M" || fail "generatedFrom != HEAD"
grep -q '"path": "context/canon/brand"' "$M"      || fail "brand domain missing"
grep -q '"kinds": \["brand-voice", "naming"\]' "$M" || fail "kinds not parsed"
grep -q '"title": "Brand"' "$M"                    || fail "title not parsed"
grep -q '"band": "cheap"' "$M"                     || fail "brand should be cheap"
grep -q '"band": "expensive"' "$M"                 || fail "tracker should be expensive"
# anchored to the 4-space unclassified entry format (gen-manifest.sh's parsing contract) — the
# unanchored substring also matched the domain's own "path" line, so this could never fail
grep -qE '^    "context/derived/tracker",?$' "$M"  || fail "tracker not listed unclassified"
grep -q '{ "path": "voice.md", "title": "Voice & tone", "tokens": [0-9]* }' "$M" \
  || fail "file entry not single-line per contract"
# escaping test: quoted domain title
grep -q '"title": "The \\"Weird\\" Domain"' "$M"   || fail "quoted domain title not properly escaped"
# escaping test: quoted file heading
grep -q '"title": "Escaping \\"Quotes\\" Works"' "$M" || fail "quoted file heading not properly escaped"
# escaping test: a backslash must survive as \\ so the manifest stays parseable
grep -q '"title": "Back\\\\slash \\"and quote\\""' "$M" \
  || fail "backslash in a title not properly escaped"
# --- schema 2: honest token accounting ---
grep -q '^  "schema": 3,$' "$M"                    || fail "schema version not declared"
grep -q '{ "path": "data.json", "title": "data.json", "tokens": [0-9]* }' "$M" \
  || fail "emitted .json data file not counted in files[]"
python3 - "$M" <<'PYEOF' || fail "schema 2 arithmetic wrong"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["schema"] == 3, m.get("schema")
d = next(x for x in m["domains"] if x["path"] == "context/derived/budget")
assert d["tokens"] == d["docTokens"] + d["indexTokens"], d
assert d["docTokens"] == sum(f["tokens"] for f in d["files"]), d
assert d["indexTokens"] > 0, "_index.md must count toward the domain total"
# the schema 1 regression this guards: docTokens alone bands cheap, the honest total does not
assert d["docTokens"] < 3000 <= d["tokens"], d
assert d["band"] == "normal", d["band"]
PYEOF

# --- schema 3: the map can say whether it is current, and where it looked ---
grep -q '^  "contextRoot": "context",$' "$M"       || fail "contextRoot not stamped"
fp=$(sed -n 's/^  "contextFingerprint": "\(.*\)",$/\1/p' "$M")
[ -n "$fp" ]                                       || fail "contextFingerprint empty on a real brain"
[ "$fp" = "$(git rev-parse HEAD:context)" ] \
  || fail "contextFingerprint is not the context tree oid (FINGERPRINT CONTRACT broken)"
# generatedFrom survives as provenance, but nothing compares against it any more
grep -q '"generatedFrom": "'"$(git rev-parse HEAD)"'"' "$M" || fail "generatedFrom dropped"

# THE REGRESSION THIS EXISTS FOR. /sync lands the derived change and the regenerated manifest
# in ONE commit, so no commit-sha scheme can ever match: the sha carrying the manifest is
# unknowable while writing the manifest. Content addressing must survive it.
mkdir -p context/derived/fresh
{ echo '---'; echo 'kinds: [repo-summaries]'; echo 'title: Fresh'; echo '---'; } \
  > context/derived/fresh/_index.md
printf '# Doc\nfresh words arrive here\n' > context/derived/fresh/doc.md
bash "$GEN" > /dev/null
# the throwaway index must not leak: nothing may be staged by generating
git status --porcelain | grep -q '^A' && fail "gen-manifest staged files (throwaway index leaked)"
git add -A; git commit -q -m "sync: content + manifest in one commit"
fp=$(sed -n 's/^  "contextFingerprint": "\(.*\)",$/\1/p' "$M")
[ "$fp" = "$(git rev-parse HEAD:context)" ] \
  || fail "same-commit sync flow leaves a permanently-false staleness signal"

# content changed after generation -> the fingerprint must NOT match, or the warning is dead
printf '# Doc\nfresh words arrive here, and then more of them\n' > context/derived/fresh/doc.md
git add -A; git commit -q -m "edit content without regenerating"
[ "$fp" = "$(git rev-parse HEAD:context)" ] \
  && fail "fingerprint unchanged after a real content change — staleness can never fire"

# idempotent: two consecutive runs produce identical output. Regenerate first so this holds
# wherever it sits in the file, rather than depending on the manifest on disk being current.
bash "$GEN" > /dev/null
cp "$M" /tmp/m1.$$; bash "$GEN"; diff -q "$M" /tmp/m1.$$ > /dev/null || fail "not deterministic"
rm -f /tmp/m1.$$
# --- configurable context root (docs/specs/2026-09-09-audit-hardening.md, configurable root) ---
mkdir -p docs/canon/x
{ echo '---'; echo 'kinds: [naming]'; echo 'title: X'; echo '---'; } > docs/canon/x/_index.md
printf '# Doc\nsome words under a non-default root\n' > docs/canon/x/doc.md
git add -A; git commit -q -m "docs root"
BRAIN_CONTEXT_DIR=docs bash "$GEN" > /dev/null || fail "generator failed with BRAIN_CONTEXT_DIR"
grep -q '^  "contextRoot": "docs",$' "$M"          || fail "BRAIN_CONTEXT_DIR not recorded"
grep -q '"path": "docs/canon/x"' "$M"              || fail "domain under the configured root missing"
grep -q '"path": "context/' "$M"                   && fail "default root leaked into a docs-root manifest"
fp=$(sed -n 's/^  "contextFingerprint": "\(.*\)",$/\1/p' "$M")
[ "$fp" = "$(git rev-parse HEAD:docs)" ]           || fail "fingerprint not taken from the configured root"

# The root must PERSIST. The env var is not committed and every documented regenerate path
# (/sync, /upgrade §5a, the README) calls the generator bare -- which used to silently revert
# the root to `context` and emit a zero-domain map whose only symptom was a staleness warning.
bash "$GEN" > /dev/null                            || fail "bare re-run failed"
grep -q '^  "contextRoot": "docs",$' "$M"          || fail "contextRoot not read back from the committed manifest"
grep -q '"path": "docs/canon/x"' "$M"              || fail "bare re-run lost the configured root's domains"

# --- everything below on a fresh brain, so the docs-root state above cannot leak in ---
B2="$TMP/brain2"; mkdir -p "$B2"; cd "$B2"; git init -q
mkdir -p context/canon/quoted context/canon/block context/canon/deep context/derived/ds context/derived/orphan/sub

# YAML has three ordinary spellings for a list and the parser used to accept exactly one.
# Quoted flow lists emitted ""a"" -- an INVALID-JSON manifest that every reader in this repo
# hid by stripping quotes, so only a real JSON consumer (a tier-2 pointer) ever saw it.
printf -- '---\nkinds: ["brand-voice", "naming"]\ntitle: Quoted\n---\n' > context/canon/quoted/_index.md
printf '# Q\nsome words here\n' > context/canon/quoted/q.md
printf -- '---\ntitle: Block\nkinds:\n  - design-system\n  - art-direction\n---\n' > context/canon/block/_index.md
printf '# B\nsome words here\n' > context/canon/block/b.md
{ echo '---'; i=1; while [ $i -le 22 ]; do echo "filler$i: x"; i=$((i+1)); done
  echo 'kinds: [analytics]'; echo 'title: Deep'; echo '---'; } > context/canon/deep/_index.md
printf '# D\nsome words here\n' > context/canon/deep/d.md
printf -- '---\nkinds: [design-system]\ntitle: DS\n---\n' > context/derived/ds/_index.md
python3 -c "import json;print(json.dumps({('k%d'%i):'v' for i in range(400)},indent=2))" > context/derived/ds/tokens.json
printf '# stray\nnobody indexed this\n' > context/derived/orphan/sub/stray.md
git remote add origin "https://jordan:ghp_TOKENTOKENTOKEN1234@github.com/acme/brain.git"
git add -A; git commit -q -m fixture2
bash "$GEN" > /dev/null || fail "generator failed on the parsing fixture"
M2=.brainforge/brain-manifest.json
python3 -m json.tool "$M2" > /dev/null            || fail "quoted kinds produced an INVALID JSON manifest"
grep -q '"kinds": \["brand-voice", "naming"\]' "$M2"        || fail "quoted flow list not normalized"
grep -q '"kinds": \["design-system", "art-direction"\]' "$M2" || fail "block list not parsed"
grep -q '"kinds": \["analytics"\]' "$M2"                     || fail "kinds below line 20 not parsed"
grep -qE '^    "context/canon/(deep|block|quoted)",?$' "$M2"  && fail "a parseable domain was called unclassified"

# A credential in remote.origin.url used to be committed verbatim into an artifact every
# subscriber clones. Nothing reads this field but its basename.
grep -q 'ghp_TOKENTOKENTOKEN1234' "$M2"           && fail "credential leaked into the manifest"
grep -q '"remote": "https://github.com/acme/brain.git",' "$M2" || fail "remote not normalized"

# The band the reader acts on is computed from the token figure, and the word-based estimate
# under-reads punctuation-dense JSON several-fold.
json_tok=$(grep -o '"path": "tokens.json", "title": "[^"]*", "tokens": [0-9]*' "$M2" | grep -o '[0-9]*$')
json_words=$(wc -w < context/derived/ds/tokens.json | tr -d ' ')
[ "$json_tok" -gt $(( (json_words * 4 + 2) / 3 )) ] || fail "json token estimate is still the word-based one"

# Content with no _index.md is invisible to the map while the fingerprint reports it current.
grep -qE '^    "context/derived/orphan/sub",?$' "$M2" || fail "unindexed directory not reported"

# A root that does not resolve must yield an EMPTY fingerprint, not git's echoed argument --
# the difference between "cannot check" and a confident wrong answer.
BRAIN_CONTEXT_DIR=nosuchroot bash "$GEN" > /dev/null 2>&1 || true
grep -q '^  "contextFingerprint": "",$' "$M2"     || fail "unresolvable root must give an empty fingerprint"

# --- every string is escaped, so the manifest is always valid JSON (see docs/specs/2026-09-11-backlog-remediation.md D5) ---
# esc_case <case> <brain dir> <title> <kinds line>: a one-domain brain, generated and JSON-checked
esc_case() {
  mkdir -p "$2/context/canon/x"; cd "$2"; git init -q
  printf -- '---\ntitle: %s\n%s\n---\n' "$3" "$4" > context/canon/x/_index.md
  printf '# Doc\nsome words here\n' > context/canon/x/doc.md
  git add -A; git commit -q -m fixture
  bash "$GEN" > /dev/null || fail "$1: generator exited non-zero"
  python3 -m json.tool .brainforge/brain-manifest.json > /dev/null || fail "$1: manifest is not valid JSON"
}
esc_case "backslash in kinds" "$TMP/esc-kinds" 'X' 'kinds: [back\slash]'
grep -q '"kinds": \["back\\\\slash"\]' .brainforge/brain-manifest.json || fail "backslash in kinds not escaped"
esc_case "quote in a title" "$TMP/esc-title" 'Say "hi"' 'kinds: [naming]'
grep -q '"title": "Say \\"hi\\""' .brainforge/brain-manifest.json || fail "quote in a title not escaped"
esc_case "tab in the brain name" "$TMP/esc$(printf '\t')brain" 'X' 'kinds: [naming]'
grep -q '^  "brain": "esc\\tbrain",$' .brainforge/brain-manifest.json || fail "tab in the brain name not escaped"

echo "PASS gen-manifest"
