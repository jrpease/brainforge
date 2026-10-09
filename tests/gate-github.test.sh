#!/usr/bin/env bash
# Test gate-github.sh against a local bare origin. Offline: the clone's origin URL looks like
# GitHub, and a clone-local url.insteadOf rewrites it to the bare repo; GIT_ALLOW_PROTOCOL=file
# makes any other transport fail rather than reach the network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="${GATE:-$ROOT/scaffold/.brainforge/gate-github.sh}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
mkdir -p "$HOME"
REMOTE="https://github.com/acme/web.git"

# fresh: a bare origin, a seed repo that pushes to it, a clone wired to it, and an empty brain
fresh() {
  rm -rf "$TMP/w"; mkdir -p "$TMP/w"
  git init -q --bare -b main "$TMP/w/origin.git"
  git init -q -b main "$TMP/w/seed"
  git -C "$TMP/w/seed" remote add origin "$TMP/w/origin.git"
  commit "README.md" "hello"
  git clone -q "file://$TMP/w/origin.git" "$TMP/w/clone"
  git -C "$TMP/w/clone" remote set-url origin "$REMOTE"
  git -C "$TMP/w/clone" config "url.file://$TMP/w/origin.git.insteadOf" "$REMOTE"
  mkdir -p "$TMP/w/brain"
}
# commit <path> <content>: commit one file in the seed and push it
commit() {
  mkdir -p "$(dirname "$TMP/w/seed/$1")"; printf '%s\n' "$2" > "$TMP/w/seed/$1"
  git -C "$TMP/w/seed" add -A; git -C "$TMP/w/seed" commit -qm "$1"
  git -C "$TMP/w/seed" push -q -f origin main
}
head_sha() { git -C "$TMP/w/seed" rev-parse HEAD; }
# sources <entries-json>; state <repos-slot-json>
sources() { printf '{ "version": 1, "repos": [%s] }\n' "$1" > "$TMP/w/brain/sources.json"; }
entry() { printf '{ "id": "%s", "remote": "%s", "localClone": "%s", "branch": "main", "into": "context/derived/repos/" }' "$1" "${2:-github.com/acme/web}" "${3:-$TMP/w/clone}"; }
state() { printf '{ "version": 1, "repos": %s }\n' "$1" > "$TMP/w/brain/.sync-state.json"; }
gate() { (cd "$TMP/w/brain" && bash "$GATE" "$@"); }
# field <json-line> <python-expr over j>
field() { python3 -c 'import json,sys; j=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2"; }

# --- (a) unchanged: stored lastSha == origin HEAD -> unchanged, empty delta ---
fresh; sources "$(entry web)"; state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"
out=$(gate web)
[ "$(echo "$out" | wc -l | tr -d ' ')" = 1 ]          || fail "(a) one id, one line (got: $out)"
[ "$(field "$out" 'j["status"]')" = unchanged ]        || fail "(a) must be unchanged (got: $out)"
[ "$(field "$out" 'j["delta"]')" = "[]" ]              || fail "(a) delta must be empty (got: $out)"
[ "$(field "$out" 'j["fingerprint"]["lastSha"]')" = "$(head_sha)" ] || fail "(a) fingerprint is origin HEAD"
[ "$(field "$out" 'j["type"]+" "+j["id"]')" = "github web" ] || fail "(a) type and id (got: $out)"

# --- (b) one in-scope commit -> changed, delta = [that path], fingerprint = new HEAD ---
old=$(head_sha); state "{ \"web\": { \"lastSha\": \"$old\" } }"
commit "src/app.ts" "x"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = changed ]          || fail "(b) must be changed (got: $out)"
[ "$(field "$out" 'j["delta"]')" = "['src/app.ts']" ]  || fail "(b) delta must be the one path (got: $out)"
[ "$(field "$out" 'j["fingerprint"]["lastSha"]')" = "$(head_sha)" ] || fail "(b) fingerprint must be new origin HEAD"
[ "$(field "$out" 'j["stored"]["lastSha"]')" = "$old" ] || fail "(b) stored must echo the slot"
[ "$(field "$out" 'j["excluded"]')" = 0 ]              || fail "(b) nothing excluded"
grep -q "$old" "$TMP/w/brain/.sync-state.json"         || fail "(b) the gate must never write .sync-state.json"

# --- (c0) the example printed in github.md §0b parses as-is (trailing comments on key lines) ---
fresh
DOC_YML=$(awk '/brainforge-source.yml/{f=1} f&&/^```yaml/{p=1;next} p&&/^```/{exit} p' "$ROOT/scaffold/pipeline/adapters/github.md")
echo "$DOC_YML" | grep -q '^summarize: *#'             || fail "(c0) could not extract the documented example from github.md"
commit ".brainforge-source.yml" "$DOC_YML"
state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"; sources "$(entry web)"
commit "docs/guide.md" "x"
out=$(gate)
[ "$(field "$out" 'j["status"]')" = changed ]          || fail "(c0) the documented example must parse, not block (got: $out)"

# --- (c) a change only under calls/ with never-summarize -> unchanged, excluded 1, never named ---
fresh
commit ".brainforge-source.yml" 'version: 1
never-summarize:
  - "calls/**"        # interviews'
state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"; sources "$(entry web)"
commit "calls/2026-10-01-interview.md" "secret"
out=$(gate)
[ "$(field "$out" 'j["status"]')" = unchanged ]        || fail "(c) excluded-only change must be unchanged (got: $out)"
[ "$(field "$out" 'j["excluded"]')" = 1 ]              || fail "(c) excluded must be 1 (got: $out)"
[ "$(field "$out" 'j["delta"]')" = "[]" ]              || fail "(c) delta must be empty (got: $out)"
echo "$out" | grep -q "calls/" && fail "(c) stdout must never name an excluded path (got: $out)"
# and a mixed change keeps only the in-scope path
commit "docs/guide.md" "g"; commit "calls/second.md" "s"
out=$(gate web)
[ "$(field "$out" 'j["delta"]')" = "['docs/guide.md']" ] || fail "(c) mixed delta must hold only docs/guide.md (got: $out)"
[ "$(field "$out" 'j["excluded"]')" = 2 ]              || fail "(c) mixed excluded must be 2 (got: $out)"
echo "$out" | grep -q "calls/" && fail "(c) mixed stdout must never name calls/"
# summarize narrows (intersected): outside it counts as excluded
commit ".brainforge-source.yml" 'version: 1
never-summarize: []
summarize:
  - '"'"'docs/**'"'"
state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"
commit "docs/a.md" "a"; commit "src/b.ts" "b"
out=$(gate web)
[ "$(field "$out" 'j["delta"]')" = "['docs/a.md']" ]   || fail "(c) summarize must narrow to docs/** (got: $out)"
[ "$(field "$out" 'j["excluded"]')" = 1 ]              || fail "(c) outside-summarize path counts as excluded (got: $out)"

# --- (d) malformed yml -> blocked (fail closed), for every malformation class ---
for bad in 'never-summarize:\n  - "calls/**"' \
           'version: 2\nnever-summarize:\n  - "calls/**"' \
           'version: 1\nnever-summarize:\n  - calls/**' \
           'version: 1\nnever-sumarize:\n  - "calls/**"' \
           'version: 1\nnever-summarize: ["calls/**"]' \
           'version: 1\n  - "calls/**"' \
           'version: 1\nnever-summarize:\n  - "calls/**"\nnever-summarize:\n  - "x/**"'; do
  fresh; sources "$(entry web)"; state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"
  commit ".brainforge-source.yml" "$(printf "$bad")"
  out=$(gate web)
  [ "$(field "$out" 'j["status"]')" = blocked ]        || fail "(d) malformed yml must block: $bad (got: $out)"
  field "$out" 'j["reason"]' | grep -q "brainforge-source.yml" || fail "(d) reason must name the file (got: $out)"
done
# a never-synced repo with a malformed yml is blocked too, not handed to extraction
state '{}'; out=$(gate web)
[ "$(field "$out" 'j["status"]')" = blocked ]          || fail "(d) malformed yml must block a never-synced entry too (got: $out)"

# --- (e) remote mismatch -> blocked, and no fetch happens ---
fresh; state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"
sources "$(entry web github.com/acme/other)"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = blocked ]          || fail "(e) remote mismatch must block (got: $out)"
field "$out" 'j["reason"]' | grep -q "does not match"  || fail "(e) reason must say mismatch (got: $out)"
# equivalent spellings of the same repo all match
for r in "github.com/acme/web" "https://github.com/acme/web" "https://GitHub.com/acme/web.git/" "git@github.com:acme/web.git" "ssh://git@github.com/acme/web" "ssh://git@github.com:22/acme/web.git"; do
  sources "$(entry web "$r")"
  out=$(gate web)
  [ "$(field "$out" 'j["status"]')" = unchanged ]      || fail "(e) remote '$r' must match the clone's origin (got: $out)"
done
# an scp-style origin whose org starts with a digit: the colon is the separator, not a port
for o in "git@github.com:1password/foo.git" "ssh://git@github.com:22/1password/foo.git"; do
  git -C "$TMP/w/clone" remote set-url origin "$o"
  git -C "$TMP/w/clone" config "url.file://$TMP/w/origin.git.insteadOf" "$o"
  for r in "github.com/1password/foo" "git@github.com:1password/foo.git" "ssh://git@github.com:22/1password/foo.git"; do
    sources "$(entry web "$r")"
    out=$(gate web)
    [ "$(field "$out" 'j["status"]')" = unchanged ]    || fail "(e) origin '$o' must match remote '$r' (got: $out)"
  done
done
git -C "$TMP/w/clone" remote set-url origin "git@github.com:42/foo.git"
sources "$(entry web github.com/foo)"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = blocked ]          || fail "(e) git@github.com:42/foo must not normalize to github.com/foo (got: $out)"
field "$out" 'j["reason"]' | grep -q "does not match"  || fail "(e) 42/foo reason must say mismatch (got: $out)"

# --- (f) no slot -> never, fingerprint present; also no state file at all ---
fresh; sources "$(entry web)"; state '{}'
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = never ]            || fail "(f) no slot must be never (got: $out)"
[ "$(field "$out" 'j["fingerprint"]["lastSha"]')" = "$(head_sha)" ] || fail "(f) never still carries the fingerprint"
rm "$TMP/w/brain/.sync-state.json"
[ "$(field "$(gate web)" 'j["status"]')" = never ]     || fail "(f) no state file must be never"

# --- (g) dirty, behind working tree: the result comes from the fetched ref ---
fresh
commit ".brainforge-source.yml" 'version: 1
never-summarize:
  - "calls/**"'
git -C "$TMP/w/clone" fetch -q; git -C "$TMP/w/clone" reset -q --hard origin/main
state "{ \"web\": { \"lastSha\": \"$(head_sha)\" } }"; sources "$(entry web)"
commit "docs/new.md" "n"; commit "calls/c.md" "c"
printf 'this is: [not the subset\n' > "$TMP/w/clone/.brainforge-source.yml"   # dirty, malformed
printf 'local edit\n' > "$TMP/w/clone/README.md"; printf 'u\n' > "$TMP/w/clone/untracked.md"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = changed ]          || fail "(g) must read the fetched ref, not the dirty tree (got: $out)"
[ "$(field "$out" 'j["delta"]')" = "['docs/new.md']" ] || fail "(g) delta from the fetched diff only (got: $out)"
[ "$(field "$out" 'j["excluded"]')" = 1 ]              || fail "(g) fetched-ref yml must apply (got: $out)"
[ ! -f "$TMP/w/clone/docs/new.md" ]                    || fail "(g) the gate must never check out or pull"
grep -q "local edit" "$TMP/w/clone/README.md"          || fail "(g) the gate must not touch the working tree"

# --- (h) force-push drops the stored lastSha -> blocked ---
fresh; commit "src/one.ts" "1"
gone=$(head_sha)
git -C "$TMP/w/clone" fetch -q   # the clone has seen the soon-dropped commit
git -C "$TMP/w/seed" reset -q --hard HEAD~1; commit "src/two.ts" "2"
sources "$(entry web)"; state "{ \"web\": { \"lastSha\": \"$gone\" } }"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = blocked ]          || fail "(h) lastSha off the fetched history must block (got: $out)"
[ "$(field "$out" 'j["reason"]')" = "lastSha not in fetched history" ] || fail "(h) reason (got: $out)"
state '{ "web": { "lastSha": "0123456789abcdef0123456789abcdef01234567" } }'
[ "$(field "$(gate web)" 'j["status"]')" = blocked ]   || fail "(h) an unknown lastSha must block"

# --- (i) two ids on one call -> two JSON lines, one per entry; no ids = every enabled entry ---
fresh; s=$(head_sha); commit "src/x.ts" "x"
sources "$(entry web), $(entry site), $(entry off) "
python3 - "$TMP/w/brain/sources.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["repos"][2]["enabled"] = False; json.dump(d, open(p, "w"))
PY
state "{ \"web\": { \"lastSha\": \"$s\" }, \"site\": { \"lastSha\": \"$(head_sha)\" } }"
out=$(gate web site)
[ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ]           || fail "(i) two ids must give two lines (got: $out)"
[ "$(field "$(echo "$out" | sed -n 1p)" 'j["id"]+":"+j["status"]')" = "web:changed" ]    || fail "(i) line 1 (got: $out)"
[ "$(field "$(echo "$out" | sed -n 2p)" 'j["id"]+":"+j["status"]')" = "site:unchanged" ] || fail "(i) line 2 (got: $out)"
out=$(gate)
[ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ]           || fail "(i) no ids gates every enabled entry, skipping disabled (got: $out)"

# --- (j) the branch tracks a second remote: the gate still fetches origin, not the upstream ---
fresh; s=$(head_sha)
git init -q --bare -b main "$TMP/w/fork.git"
git -C "$TMP/w/seed" push -q "$TMP/w/fork.git" main
git -C "$TMP/w/clone" remote add fork "file://$TMP/w/fork.git"
git -C "$TMP/w/clone" fetch -q fork; git -C "$TMP/w/clone" branch -q -u fork/main main
commit "src/later.ts" "l"   # origin moves on; fork does not
sources "$(entry web)"; state "{ \"web\": { \"lastSha\": \"$s\" } }"
out=$(gate web)
[ "$(field "$out" 'j["status"]')" = changed ]          || fail "(j) must fetch origin even when main tracks another remote (got: $out)"
[ "$(field "$out" 'j["delta"]')" = "['src/later.ts']" ] || fail "(j) delta from origin (got: $out)"

# --- (k) the fetch can never stop on a credential prompt: no terminal prompt, BatchMode ssh ---
mkdir -p "$TMP/spy"; REALGIT=$(command -v git)
printf '#!/bin/sh\necho "$GIT_TERMINAL_PROMPT|$GIT_SSH_COMMAND" >> "%s"\nexec "%s" "$@"\n' "$TMP/spy/log" "$REALGIT" > "$TMP/spy/git"
chmod +x "$TMP/spy/git"; : > "$TMP/spy/log"
PATH="$TMP/spy:$PATH" gate web >/dev/null
[ -s "$TMP/spy/log" ]                                  || fail "(k) spy git never ran"
! grep -qv '^0|ssh -oBatchMode=yes$' "$TMP/spy/log"    || fail "(k) every git call must run without prompts (got: $(sort -u "$TMP/spy/log"))"
: > "$TMP/spy/log"
GIT_SSH_COMMAND="ssh -i k" PATH="$TMP/spy:$PATH" gate web >/dev/null
[ -s "$TMP/spy/log" ]                                  || fail "(k) spy git never ran (pre-set GIT_SSH_COMMAND)"
! grep -qv '^0|ssh -i k -oBatchMode=yes$' "$TMP/spy/log" || fail "(k) an owner's GIT_SSH_COMMAND must be kept, BatchMode appended (got: $(sort -u "$TMP/spy/log"))"

# --- not-checked: no clone, and fetch failure (offline) ---
sources "$(entry web github.com/acme/web "$TMP/w/missing")"
[ "$(field "$(gate web)" 'j["status"]+":"+j["reason"]')" = "not-checked:no clone" ] || fail "missing clone -> not-checked (no clone)"
[ "$(field "$(gate web)" 'str(j["delta"] == [] and j["excluded"] == 0)')" = True ] || fail "not-checked must print delta [] and excluded 0, not null"
sources '{ "id": "web", "remote": "github.com/acme/web", "into": "context/derived/repos/" }'
[ "$(field "$(gate web)" 'j["status"]+":"+j["reason"]')" = "not-checked:no clone" ] || fail "no localClone -> not-checked (no clone)"
sources "$(entry web)"; mv "$TMP/w/origin.git" "$TMP/w/origin.moved"
[ "$(field "$(gate web)" 'j["status"]+":"+j["reason"]')" = "not-checked:offline" ] || fail "failed fetch -> not-checked (offline)"
mv "$TMP/w/origin.moved" "$TMP/w/origin.git"

# --- misuse: unknown id or no sources.json -> exit 1, stderr, nothing on stdout ---
rc=0; out=$(gate web nope 2>"$TMP/err") || rc=$?
[ "$rc" = 1 ] && [ -z "$out" ]                         || fail "unknown id must exit 1 with no stdout (rc=$rc)"
grep -q "^gate-github: unknown repos id(s): nope$" "$TMP/err" || fail "unknown id must be named on stderr (got: $(cat "$TMP/err"))"
rm "$TMP/w/brain/sources.json"
rc=0; gate >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ]                                          || fail "no sources.json must exit 1"

echo "PASS gate-github"
