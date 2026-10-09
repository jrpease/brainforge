#!/usr/bin/env bash
# regen-if-stale.sh: regenerate the manifest only when the reader would call it stale, and
# never hand the reader a map it cannot check. Fixture brains use the shipped gen-manifest.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAF="$ROOT/scaffold"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
bad=0
fail() { echo "FAIL: $1"; bad=1; }
g() { git -c user.email=fx@fx -c user.name=fx "$@"; }

brain() { # <dir>: a committed brain with one domain and a fresh, committed map
  mkdir -p "$1/.brainforge" "$1/context/canon/brand"
  cp "$SCAF/.brainforge/gen-manifest.sh" "$SCAF/.brainforge/regen-if-stale.sh" "$1/.brainforge/"
  printf -- '---\nkinds: [brand-voice]\ntitle: Brand\n---\n' > "$1/context/canon/brand/_index.md"
  printf '# Voice\nPlain words.\n' > "$1/context/canon/brand/voice.md"
  ( cd "$1" && git init -q && git add -A && g commit -qm content \
    && bash .brainforge/gen-manifest.sh > /dev/null && git add -A && g commit -qm map )
}
run() { ( cd "$1" && bash .brainforge/regen-if-stale.sh 2> "$TMP/err" ); }
fp() { sed -n 's/^  "contextFingerprint": "\(.*\)",$/\1/p' "$1/.brainforge/brain-manifest.json"; }
head_fp() { git -C "$1" rev-parse "HEAD:${2:-context}"; }

# (a) a fresh committed map is left alone, byte for byte
brain "$TMP/a"; cp "$TMP/a/.brainforge/brain-manifest.json" "$TMP/a.before"
out=$(run "$TMP/a"); [ "$out" = "CURRENT" ] || fail "(a) fresh map: got '$out'"
cmp -s "$TMP/a.before" "$TMP/a/.brainforge/brain-manifest.json" || fail "(a) fresh map was rewritten"

# (b) content committed after the map -> regenerated, and the new map is current
brain "$TMP/b"; printf 'More.\n' >> "$TMP/b/context/canon/brand/voice.md"; ( cd "$TMP/b" && g commit -qam more )
out=$(run "$TMP/b"); case "$out" in "REGENERATED "*) ;; *) fail "(b) stale map: got '$out'" ;; esac
[ "$(fp "$TMP/b")" = "$(head_fp "$TMP/b")" ] || fail "(b) new fingerprint is not HEAD:context"

# (c) the conflict the roadmap describes: two branches each regenerate, the merge keeps one side
brain "$TMP/c"
( cd "$TMP/c" && git checkout -qb one && printf 'one\n' > context/canon/brand/one.md \
  && bash .brainforge/gen-manifest.sh > /dev/null && git add -A && g commit -qm one \
  && git checkout -q - && git checkout -qb two && printf 'two\n' > context/canon/brand/two.md \
  && bash .brainforge/gen-manifest.sh > /dev/null && git add -A && g commit -qm two \
  && git checkout -q one && { g merge -q two > /dev/null 2>&1 || true; } \
  && git checkout --ours -- .brainforge/brain-manifest.json && git add -A && g commit -qm merge )
[ "$(fp "$TMP/c")" != "$(head_fp "$TMP/c")" ] || fail "(c) fixture did not reproduce the stale merge"
out=$(run "$TMP/c"); case "$out" in "REGENERATED "*) ;; *) fail "(c) merged map: got '$out'" ;; esac
[ "$(fp "$TMP/c")" = "$(head_fp "$TMP/c")" ] || fail "(c) merged map still stale"

# (d) a schema-2 map (no fingerprint line) -> regenerated
brain "$TMP/d"; sed -i.bak '/"contextFingerprint"/d' "$TMP/d/.brainforge/brain-manifest.json"; rm "$TMP/d/.brainforge/brain-manifest.json.bak"
( cd "$TMP/d" && g commit -qam schema2 )
out=$(run "$TMP/d"); case "$out" in "REGENERATED none -> "*) ;; *) fail "(d) pre-schema-3 map: got '$out'" ;; esac

# (e) no generator -> silent success (a brain older than the manifest)
mkdir -p "$TMP/e/.brainforge"; cp "$SCAF/.brainforge/regen-if-stale.sh" "$TMP/e/.brainforge/"; ( cd "$TMP/e" && git init -q )
out=$(run "$TMP/e"); rc=$?; [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "(e) no generator: rc=$rc out='$out'"

# (f) a configured context root is honoured, from the env the first time and the manifest after
mkdir -p "$TMP/f/.brainforge" "$TMP/f/docs/guides"
cp "$SCAF/.brainforge/gen-manifest.sh" "$SCAF/.brainforge/regen-if-stale.sh" "$TMP/f/.brainforge/"
printf -- '---\nkinds: [brand-voice]\ntitle: Guides\n---\n' > "$TMP/f/docs/guides/_index.md"
( cd "$TMP/f" && git init -q && git add -A && g commit -qm content )
out=$(cd "$TMP/f" && BRAIN_CONTEXT_DIR=docs bash .brainforge/regen-if-stale.sh 2>/dev/null)
case "$out" in "REGENERATED none -> "*) ;; *) fail "(f) custom root first run: got '$out'" ;; esac
( cd "$TMP/f" && git add -A && g commit -qm map )
out=$(run "$TMP/f"); [ "$out" = "CURRENT" ] || fail "(f) custom root from manifest: got '$out'"
[ "$(fp "$TMP/f")" = "$(head_fp "$TMP/f" docs)" ] || fail "(f) fingerprint is not HEAD:docs"

# (g) idempotent: once regenerated and committed, the next run is CURRENT (no daily churn)
( cd "$TMP/b" && git add -A && g commit -qm regen )
out=$(run "$TMP/b"); [ "$out" = "CURRENT" ] || fail "(g) second run: got '$out'"

# (h) a context root with nothing committed -> exit 1, never a quiet success
mkdir -p "$TMP/h/.brainforge"; cp "$SCAF/.brainforge/gen-manifest.sh" "$SCAF/.brainforge/regen-if-stale.sh" "$TMP/h/.brainforge/"
( cd "$TMP/h" && git init -q && git add -A && g commit -qm scripts )
out=$(run "$TMP/h"); rc=$?
[ "$rc" -eq 1 ] || fail "(h) empty root: rc=$rc out='$out'"
case "$out" in REGENERATED*) fail "(h) empty root reported as fixed" ;; esac
grep -q 'not a tree in HEAD' "$TMP/err" || fail "(h) exit 1 was not the empty-fingerprint refusal"

# (i) an untracked file under the root: the generator counts it, HEAD does not -> exit 1
brain "$TMP/i"; printf 'More.\n' >> "$TMP/i/context/canon/brand/voice.md"; ( cd "$TMP/i" && g commit -qam more )
printf 'draft\n' > "$TMP/i/context/canon/brand/untracked.md"
out=$(run "$TMP/i"); rc=$?
[ "$rc" -eq 1 ] || fail "(i) untracked content: rc=$rc out='$out'"
grep -q 'does not match HEAD' "$TMP/err" || fail "(i) exit 1 was not the fingerprint-mismatch refusal"

# (j) a generator older than schema 3 (writes no fingerprint key) -> exit 1, and says so
brain "$TMP/j"; for f in gen-manifest.sh brain-manifest.json; do  # an old generator and the map it wrote
  sed -i.bak '/contextFingerprint/d' "$TMP/j/.brainforge/$f"; rm "$TMP/j/.brainforge/$f.bak"; done
( cd "$TMP/j" && g commit -qam "old generator" )
out=$(run "$TMP/j"); rc=$?
[ "$rc" -eq 1 ] || fail "(j) old generator: rc=$rc out='$out'"
grep -q 'predates schema 3' "$TMP/err" || fail "(j) old generator misdiagnosed: $(cat "$TMP/err")"

# the workflow: parses, calls the script, can write, only runs on the default branch
WF="$SCAF/.github/workflows/brainforge-manifest.yml"
if [ -f "$WF" ]; then
  if command -v ruby > /dev/null; then
    ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$WF" 2>/dev/null || fail "workflow is not valid YAML"
  else
    echo "note: ruby absent, workflow YAML parse skipped"
  fi
  grep -q 'bash .brainforge/regen-if-stale.sh' "$WF" || fail "workflow does not run the script"
  grep -q 'contents: write' "$WF" || fail "workflow lacks contents: write"
  grep -q "github.event.repository.default_branch" "$WF" || fail "workflow lacks the default-branch guard"
else
  fail "workflow file missing: $WF"
fi

[ "$bad" -eq 0 ] || exit 1
echo "PASS regen-if-stale"
