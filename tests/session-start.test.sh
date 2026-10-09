#!/usr/bin/env bash
# session-start.sh: the brain's session hooks, run as one script from a thin settings.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SS="$ROOT/scaffold/.brainforge/session-start.sh"
CH="$ROOT/scaffold/.brainforge/canon-health.sh"
SETTINGS="$ROOT/scaffold/.claude/settings.json"
TMP=$(mktemp -d); trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

DRIFT='Drift watermark is empty'
SYNC='Sync health:'
CANON='Canon health'
LEGACY='still has the old inline session hooks'

# brain <name>: a git repo (no remote, so the pull always reports "could not fast-forward") with
# the scripts installed where a scaffolded brain has them.
brain() {
  local B="$TMP/$1"; mkdir -p "$B/.brainforge" "$B/.claude"
  cp "$SS" "$CH" "$B/.brainforge/"
  cp "$SETTINGS" "$B/.claude/settings.json"
  printf '{\n  "version": 1,\n  "repos": {},\n  "lastFullSync": "2026-09-01"\n}\n' > "$B/.sync-state.json"
  git -C "$B" init -q
  git -C "$B" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}
# trip <name>: trip the drift, sync-health and canon-health hooks
trip() {
  local B="$TMP/$1"
  : > "$B/.brainforge/last-drift-review"
  printf '{\n  "version": 1,\n  "repos": {\n    "web": {\n      "synced": false\n    }\n  },\n  "lastFullSync": null\n}\n' > "$B/.sync-state.json"
  mkdir -p "$B/context/canon/brand"
  printf -- '---\ntitle: T\nowner: TODO\nlast-reviewed: TODO\nstatus: approved\n---\n\n# T\n' > "$B/context/canon/brand/voice.md"
}
# run <name>: the brain's own copy of the script, via CLAUDE_PROJECT_DIR as the hook passes it
run() { CLAUDE_PROJECT_DIR="$TMP/$1" bash "$TMP/$1/.brainforge/session-start.sh"; }
has()  { printf '%s\n' "$1" | grep -qF "$2" || fail "$3 (got: $1)"; }
hasnt() { printf '%s\n' "$1" | grep -qF "$2" && fail "$3 (got: $1)"; return 0; }

# --- (a) all four hooks speak on a brain that trips each one, in today's order ---
brain all; trip all
out=$(run all) || fail "(a) script must exit 0"
has "$out" 'Context:' "(a) pull line missing"
has "$out" "$DRIFT"   "(a) drift nudge missing"
has "$out" "$SYNC"    "(a) sync-health nudge missing"
has "$out" "$CANON"   "(a) canon-health nudge missing"
order=$(printf '%s\n' "$out" | grep -oE 'Context:|Drift|Sync health|Canon health' | tr '\n' ,)
[ "$order" = "Context:,Drift,Sync health,Canon health," ] || fail "(a) hooks out of order: $order"

# --- (b) a brain that trips none prints only the pull line; also proves the ../ fallback ---
brain none
out=$(env -u CLAUDE_PROJECT_DIR bash "$TMP/none/.brainforge/session-start.sh") || fail "(b) must exit 0"
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || fail "(b) expected exactly one line (got: $out)"
has "$out" 'Context: could not fast-forward' "(b) the one line must be the pull line"
# the fallback really resolved to the brain: trip only sync health and run it unset again
printf '{\n  "version": 1,\n  "repos": {\n    "web": {\n      "synced": false\n    }\n  },\n  "lastFullSync": null\n}\n' > "$TMP/none/.sync-state.json"
out=$(env -u CLAUDE_PROJECT_DIR bash "$TMP/none/.brainforge/session-start.sh") || fail "(b) must exit 0"
has "$out" "$SYNC" "(b) without CLAUDE_PROJECT_DIR the script must fall back to its own ../"

# --- (c) one hook failing (unreadable .sync-state.json) does not suppress the others ---
brain broken; trip broken
chmod 000 "$TMP/broken/.sync-state.json"
set +e; out=$(run broken 2>&1); rc=$?; set -e
chmod 644 "$TMP/broken/.sync-state.json"
[ "$rc" -eq 0 ]       || fail "(c) script must exit 0 when a hook fails (got $rc)"
has "$out" 'Context:' "(c) pull line suppressed"
has "$out" "$DRIFT"   "(c) drift nudge suppressed by the failing hook"
has "$out" "$CANON"   "(c) canon nudge suppressed by the failing hook"

# --- (d) the legacy detector ---
brain legacy
printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "WM=\\"$CLAUDE_PROJECT_DIR/.brainforge/last-drift-review\\"" } ] } ] } }\n' \
  > "$TMP/legacy/.claude/settings.json"
out=$(run legacy) || fail "(d) must exit 0"
has "$out" "$LEGACY" "(d) legacy detector must fire on settings.json with last-drift-review"
[ "$(printf '%s\n' "$out" | grep -cF "$LEGACY")" -eq 1 ] || fail "(d) legacy line must print once"
out=$(run none) || fail "(d) must exit 0"
hasnt "$out" "$LEGACY" "(d) legacy detector must be silent on the shipped thin settings.json"
grep -q 'last-drift-review' "$SETTINGS" && fail "(d) shipped settings.json (\$comment included) names last-drift-review"
rm "$TMP/none/.claude/settings.json"
out=$(run none) || fail "(d) must exit 0 with no settings.json"
hasnt "$out" "$LEGACY" "(d) legacy detector must be silent with no settings.json"

# --- (e) the script rewritten mid-run by `git pull` still completes, and reads none of the new
# bytes. The brain's copy gets a comment block bigger than bash's read buffer right after hook 1,
# ending in a PAD-END line, so the hooks after the pull are not yet in bash's buffer when the pull
# runs. The fake pull then rewrites the file in place (same inode): everything after PAD-END
# becomes marker lines, running on past the original length. A script without the `main` wrapper
# reads its later hooks from the new bytes, and one without the trailing `; exit` reads on past
# its own end; either way the marker prints every time, not by timing luck.
brain rewrite; trip rewrite
python3 - "$TMP/rewrite/.brainforge/session-start.sh" <<'PY' || fail "(e) could not pad the script"
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "  # (2) drift gate\n"
assert s.count(anchor) == 1, "hook 2 anchor not found"
pad = "".join("  # padding line %04d, pushes the later hooks past the read buffer\n" % i for i in range(400))
open(p, "w").write(s.replace(anchor, pad + "  # PAD-END\n" + anchor))
PY
grep -q '^  # PAD-END$' "$TMP/rewrite/.brainforge/session-start.sh" || fail "(e) padding missing"
mkdir -p "$TMP/bin"
REALGIT=$(command -v git)
cat > "$TMP/bin/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = pull ]; then
    F="$TMP/rewrite/.brainforge/session-start.sh"
    orig=\$(wc -c < "\$F")
    sed -n '1,/^  # PAD-END\$/p' "\$F" > "\$F.new"
    while [ "\$(wc -c < "\$F.new")" -le "\$((orig + 200))" ]; do echo 'echo MARKER-READ-PAST-END' >> "\$F.new"; done
    cat "\$F.new" > "\$F"; rm "\$F.new"
    exit 0
  fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/bin/git"
out=$(PATH="$TMP/bin:$PATH" run rewrite) || fail "(e) must exit 0"
grep -q MARKER-READ-PAST-END "$TMP/rewrite/.brainforge/session-start.sh" || fail "(e) fake pull never ran"
has "$out" 'Context: pulled latest.' "(e) fake pull's line missing"
has "$out" "$DRIFT"  "(e) hooks after the rewrite did not run"
has "$out" "$SYNC"   "(e) hooks after the rewrite did not run"
has "$out" "$CANON"  "(e) hooks after the rewrite did not run"
hasnt "$out" MARKER-READ-PAST-END "(e) script read on into the rewritten file"

# --- (f) the thin settings.json: one hook, today's matcher, runs the script ---
python3 - "$SETTINGS" <<'PY' || fail "(f) thin settings.json is wrong"
import json, sys
cfg = json.load(open(sys.argv[1]))
ss = cfg["hooks"]["SessionStart"]
assert len(ss) == 1, "expected one SessionStart entry"
assert ss[0]["matcher"] == "startup|resume", "matcher changed: %r" % ss[0]["matcher"]
assert len(ss[0]["hooks"]) == 1, "expected one hook command"
assert ".brainforge/session-start.sh" in ss[0]["hooks"][0]["command"]
PY
# and the shipped command string itself runs the script, and is silent when the script is absent
CMD=$(python3 -c "import json;print(json.load(open('$SETTINGS'))['hooks']['SessionStart'][0]['hooks'][0]['command'])")
out=$(CLAUDE_PROJECT_DIR="$TMP/all" bash -c "$CMD") || fail "(f) shipped command must exit 0"
has "$out" "$SYNC" "(f) shipped command did not run the script"
rm "$TMP/all/.brainforge/session-start.sh"
out=$(CLAUDE_PROJECT_DIR="$TMP/all" bash -c "$CMD") || fail "(f) shipped command must exit 0 with no script"
[ -z "$out" ] || fail "(f) shipped command must be silent with no script (got: $out)"

echo "PASS session-start"
