#!/usr/bin/env bash
# Test source-signal.sh: the real gate-github.sh against a local bare origin (as in
# gate-github.test.sh), with gh replaced by tests/lib/gh-stub.sh. One case per lifecycle row.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIG="${SIG:-$ROOT/scaffold/.brainforge/source-signal.sh}"
TPL="$ROOT/scaffold/templates/source-sync-trigger.yml"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
mkdir -p "$HOME" "$TMP/bin"
ln -s "$ROOT/tests/lib/gh-stub.sh" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" GH_STUB_DIR="$TMP/gh"
REMOTE="https://github.com/acme/web.git"

fresh() {
  rm -rf "$TMP/w" "$GH_STUB_DIR"; mkdir -p "$TMP/w/brain" "$GH_STUB_DIR"
  git init -q --bare -b main "$TMP/w/origin.git"
  git init -q -b main "$TMP/w/seed"
  git -C "$TMP/w/seed" remote add origin "$TMP/w/origin.git"
  commit "README.md" "hello"
  git clone -q "file://$TMP/w/origin.git" "$TMP/w/ci"
  git -C "$TMP/w/ci" remote set-url origin "$REMOTE"
  git -C "$TMP/w/ci" config "url.file://$TMP/w/origin.git.insteadOf" "$REMOTE"
}
commit() {
  mkdir -p "$(dirname "$TMP/w/seed/$1")"; printf '%s\n' "$2" > "$TMP/w/seed/$1"
  git -C "$TMP/w/seed" add -A; git -C "$TMP/w/seed" commit -qm "$1"
  git -C "$TMP/w/seed" push -q -f origin main
}
head_sha() { git -C "$TMP/w/seed" rev-parse HEAD; }
# brain <remote> [lastSha]: one repos entry whose localClone points nowhere (CI has none)
brain() {
  printf '{ "version": 1, "repos": [{ "id": "web", "remote": "%s", "localClone": "%s", "branch": "main", "into": "context/derived/repos/" }] }\n' \
    "$1" "$TMP/w/nowhere" > "$TMP/w/brain/sources.json"
  if [ -n "${2:-}" ]; then printf '{ "version": 1, "repos": { "web": { "lastSha": "%s" } } }\n' "$2"
  else echo '{ "version": 1, "repos": {} }'; fi > "$TMP/w/brain/.sync-state.json"
}
issues() { printf '%s\n' "$1" > "$GH_STUB_DIR/issues.json"; }
# sig [args...] -> OUT (stdout), RC; runs from the brain root as the workflow does
sig() { RC=0; OUT=$(cd "$TMP/w/brain" && bash "$SIG" "${@:-web}" 2>"$TMP/err") || RC=$?; }
calls() { cat "$GH_STUB_DIR/calls.log" 2>/dev/null || true; }
ncalls() { calls | grep -c "$1" || true; }

# --- never: no lastSha -> nothing to do, no gh call at all ---
fresh; brain github.com/acme/web
sig web --clone "$TMP/w/ci"
[ "$RC" = 0 ] && case "$OUT" in "nothing to do"*) ;; *) false ;; esac || fail "never: nothing to do, exit 0 ($RC: $OUT)"
[ -z "$(calls)" ] || fail "never: must not call gh ($(calls))"

# --- changed, no open issue -> label, create, opened #7; body names the path and the compare ---
fresh; c0=$(head_sha); commit "src/a.ts" "a"; c1=$(head_sha); brain github.com/acme/web "$c0"
sig --clone "$TMP/w/ci" web
[ "$RC" = 0 ] && [ "$OUT" = "opened #7" ] || fail "changed: opened #7 ($RC: $OUT; $(cat "$TMP/err"))"
[ "$(ncalls '^issue create --title Sync needed: web --label brainforge-sync')" = 1 ] || fail "changed: one create with the title and label ($(calls))"
[ "$(ncalls '^label create brainforge-sync --force')" = 1 ] || fail "changed: ensures the label first"
grep -q '^- `src/a.ts`$' "$GH_STUB_DIR/body.last" || fail "changed: body lists the in-scope path"
grep -q "https://github.com/acme/web/compare/$c0...$c1" "$GH_STUB_DIR/body.last" || fail "changed: body carries the compare link"
grep -q 'Run `/sync` in the brain' "$GH_STUB_DIR/body.last" || fail "changed: body says what to do"

# --- changed again, issue open -> edit, never a second create ---
issues '[{"number": 7, "title": "Sync needed: web"}]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$OUT" = "updated #7" ] || fail "changed twice: updated #7 ($OUT)"
[ "$(ncalls '^issue create')" = 0 ] && [ "$(ncalls '^issue edit 7 --body-file -')" = 1 ] || fail "changed twice: edit, no create ($(calls))"
calls | grep -q '^issue list' && fail "lookup must not use gh issue list (search-backed: the index lags a fresh create)"
calls | grep -q '^api repos/{owner}/{repo}/issues?labels=brainforge-sync&state=open&per_page=100$' || fail "lookup must be the REST issues list, 100 per page ($(calls))"

# --- a pull request with the same title is not the issue (the REST list includes PRs) ---
issues '[{"number": 5, "title": "Sync needed: web", "pull_request": {}}]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$OUT" = "opened #7" ] && [ "$(ncalls '^issue edit 5')" = 0 ] || fail "a PR titled like the issue must be skipped ($OUT; $(calls))"

# --- an issue for another id whose title extends this one's is not ours ---
issues '[{"number": 9, "title": "Sync needed: web-docs"}]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$OUT" = "opened #7" ] && [ "$(ncalls '^issue edit 9')" = 0 ] || fail "title match must be exact ($OUT; $(calls))"

# --- unchanged with the issue open -> close with the caught-up comment ---
brain github.com/acme/web "$c1"; issues '[{"number": 7, "title": "Sync needed: web"}]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$RC" = 0 ] && [ "$OUT" = "closed #7" ] || fail "unchanged: closed #7 ($RC: $OUT)"
calls | grep -q "^issue close 7 --comment Caught up at \`$c1\`." || fail "unchanged: close comment names the head ($(calls))"
# ...and with none open -> nothing to do, nothing written
issues '[]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
case "$OUT" in "nothing to do"*) ;; *) fail "unchanged, no issue: nothing to do ($OUT)" ;; esac
[ "$(calls | grep -vc '^api ' || true)" = 0 ] || fail "unchanged, no issue: only the lookup ($(calls))"

# --- blocked: the clone is another repo's -> open, carrying the reason; never closed ---
brain github.com/acme/other "$c0"; issues '[]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$RC" = 0 ] && [ "$OUT" = "opened #7" ] || fail "blocked: opened ($RC: $OUT)"
grep -q 'cannot be checked: origin .* does not match remote github.com/acme/other' "$GH_STUB_DIR/body.last" || fail "blocked: body carries the reason"
issues '[{"number": 7, "title": "Sync needed: web"}]'; : > "$GH_STUB_DIR/calls.log"
sig web --clone "$TMP/w/ci"
[ "$OUT" = "updated #7" ] && [ "$(ncalls '^issue close')" = 0 ] || fail "blocked: edits, never closes ($OUT; $(calls))"

# --- the compare link from scp and scheme-less remotes; none for a non-GitHub host ---
for r in "git@github.com:acme/web.git" "github.com/acme/web" "https://github.com/acme/web"; do
  brain "$r" "$c0"; issues '[]'; sig web --clone "$TMP/w/ci"
  grep -q "https://github.com/acme/web/compare/$c0...$c1" "$GH_STUB_DIR/body.last" || fail "compare link from remote $r"
done

# --- a long delta: first 50 listed, then "and N more" ---
c0=$(head_sha)
for n in $(seq 1 52); do mkdir -p "$TMP/w/seed/many"; printf '%s\n' "$n" > "$TMP/w/seed/many/f$n.ts"; done
git -C "$TMP/w/seed" add -A; git -C "$TMP/w/seed" commit -qm many; git -C "$TMP/w/seed" push -q -f origin main
brain github.com/acme/web "$c0"; issues '[]'; sig web --clone "$TMP/w/ci"
[ "$(grep -c '^- `many/' "$GH_STUB_DIR/body.last")" = 50 ] || fail "long delta: exactly 50 paths listed"
grep -q '^- and 2 more$' "$GH_STUB_DIR/body.last" || fail "long delta: 'and 2 more'"
grep -q '^Changed in scope (52):$' "$GH_STUB_DIR/body.last" || fail "long delta: the heading counts all 52"

# --- not-checked: no clone at the path -> exit 1, no gh call ---
fresh; brain github.com/acme/web "$(head_sha)"
sig web --clone "$TMP/w/missing"
[ "$RC" = 1 ] && [ -z "$(calls)" ] || fail "not-checked: exit 1 with no gh call ($RC; $(calls))"
grep -q "not-checked (no clone)" "$TMP/err" || fail "not-checked: stderr names the status ($(cat "$TMP/err"))"

# --- a gh failure (an expired or under-scoped token) -> exit 1 ---
c0=$(head_sha); commit "src/b.ts" "b"; brain github.com/acme/web "$c0"; touch "$GH_STUB_DIR/fail"
sig web --clone "$TMP/w/ci"
[ "$RC" = 1 ] || fail "gh failure must exit 1 ($RC: $OUT)"
grep -q "gh api repos/{owner}/{repo}/issues?labels=brainforge-sync&state=open&per_page=100 failed" "$TMP/err" || fail "gh failure: stderr says which call ($(cat "$TMP/err"))"
grep -q "^source-signal (brain " "$TMP/err" || fail "a red run must name the brain ($(cat "$TMP/err"))"
rm "$GH_STUB_DIR/fail"

# --- misuse -> exit 1, no stdout ---
for a in "web" "--clone $TMP/w/ci" "web web2 --clone $TMP/w/ci" "web --clone"; do
  RC=0; OUT=$(cd "$TMP/w/brain" && bash "$SIG" $a 2>/dev/null) || RC=$?
  [ "$RC" = 1 ] && [ -z "$OUT" ] || fail "misuse '$a' must exit 1 with no stdout ($RC: $OUT)"
done

# --- the workflow template is valid YAML and names the script and the secret ---
if command -v ruby > /dev/null; then
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$TPL" 2>/dev/null || fail "template is not valid YAML"
else
  echo "note: ruby absent, template YAML parse skipped"
fi
grep -q 'bash .brainforge/source-signal.sh SOURCE_ID --clone "$GITHUB_WORKSPACE"' "$TPL" || fail "template must call the script"
grep -q 'fetch-depth: 0' "$TPL" || fail "template must check out full history (the ancestry check needs lastSha)"
[ "$(grep -c 'secrets.BRAINFORGE_BRAIN_TOKEN' "$TPL")" = 2 ] || fail "template: the secret for checkout and for gh"

echo "PASS source-signal"
