#!/usr/bin/env bash
# tripwires.sh: the drift and sync-health nudges on their own, read-only and pull-free, so a
# caller that must never write to the brain (Brainforge Studio) can run them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TW="$ROOT/scaffold/.brainforge/tripwires.sh"
SS="$ROOT/scaffold/.brainforge/session-start.sh"
CH="$ROOT/scaffold/.brainforge/canon-health.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
[ -x "$TW" ] || fail "scaffold has no executable .brainforge/tripwires.sh"

DRIFT='never had a drift review'
SYNC='Sync health:'

# brain <name>: a committed git repo with a scaffolded .brainforge/
brain() {
  local B="$TMP/$1"; mkdir -p "$B/.brainforge"
  cp "$TW" "$SS" "$CH" "$B/.brainforge/"
  printf '{\n  "version": 1,\n  "repos": {},\n  "lastFullSync": "2026-09-01"\n}\n' > "$B/.sync-state.json"
  git -C "$B" init -q
  git -C "$B" add -A
  git -C "$B" -c user.name=t -c user.email=t@t commit -q -m init
}
# trip <name>: derived content with no watermark, and a source that never synced; committed
trip() {
  local B="$TMP/$1"; mkdir -p "$B/context/derived/web"
  printf -- '---\nsource: github\n---\n\n# Web\n' > "$B/context/derived/web/repo.md"
  printf '{\n  "version": 1,\n  "repos": {\n    "web": {\n      "synced": false\n    }\n  },\n  "lastFullSync": null\n}\n' > "$B/.sync-state.json"
  git -C "$B" add -A
  git -C "$B" -c user.name=t -c user.email=t@t commit -q -m trip
}
has()  { printf '%s\n' "$1" | grep -qF "$2" || fail "$3 (got: $1)"; }
hasnt() { printf '%s\n' "$1" | grep -qF "$2" && fail "$3 (got: $1)"; return 0; }

# --- (a)+(b) a tripped brain prints both nudges, drift first; (d) exit 0 ---
brain hot; trip hot
out=$(bash "$TMP/hot/.brainforge/tripwires.sh" "$TMP/hot") || fail "(d) must exit 0 when tripped"
has "$out" "$DRIFT" "(a) drift nudge missing"
has "$out" "$SYNC"  "(b) sync-health nudge missing"
order=$(printf '%s\n' "$out" | grep -oE 'drift review|Sync health' | tr '\n' ,)
[ "$order" = "drift review,Sync health," ] || fail "(a) nudges out of order: $order"

# --- (c) a clean brain prints nothing; (d) exit 0 ---
brain clean
out=$(bash "$TMP/clean/.brainforge/tripwires.sh" "$TMP/clean") || fail "(d) must exit 0 when clean"
[ -z "$out" ] || fail "(c) clean brain must be silent (got: $out)"

# --- (e) never pulls or fetches, and leaves the tree as it found it. A watermark from an earlier
# commit sends the drift gate through git cat-file and git diff, so git calls really reach the stub.
first=$(git -C "$TMP/hot" rev-list --max-parents=0 HEAD)
printf '%s\n' "$first" > "$TMP/hot/.brainforge/last-drift-review"
git -C "$TMP/hot" add -A; git -C "$TMP/hot" -c user.name=t -c user.email=t@t commit -q -m watermark
mkdir -p "$TMP/bin"; : > "$TMP/git.log"
REALGIT=$(command -v git)
cat > "$TMP/bin/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in pull|fetch) echo "\$a" >> "$TMP/git.log"; exit 99 ;; esac
done
echo call >> "$TMP/git.calls"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/bin/git"
before=$(git -C "$TMP/hot" status --porcelain)
out=$(PATH="$TMP/bin:$PATH" bash "$TMP/hot/.brainforge/tripwires.sh" "$TMP/hot") || fail "(e) must exit 0"
has "$out" 'Context changed since last drift review' "(e) watermarked drift nudge missing"
[ -s "$TMP/git.calls" ] || fail "(e) no git call reached the stub, so the check proves nothing"
[ ! -s "$TMP/git.log" ] || fail "(e) tripwires.sh ran: $(cat "$TMP/git.log")"
after=$(git -C "$TMP/hot" status --porcelain)
[ "$before" = "$after" ] || fail "(e) working tree changed: $after"

# --- (f) $1 wins over CLAUDE_PROJECT_DIR; without either, the script's own brain ---
out=$(CLAUDE_PROJECT_DIR="$TMP/clean" bash "$TMP/clean/.brainforge/tripwires.sh" "$TMP/hot")
has "$out" "$SYNC" "(f) \$1 must win over CLAUDE_PROJECT_DIR"
out=$(CLAUDE_PROJECT_DIR="$TMP/hot" bash "$TMP/clean/.brainforge/tripwires.sh")
has "$out" "$SYNC" "(f) with no \$1, CLAUDE_PROJECT_DIR must win over the script's brain"
out=$(env -u CLAUDE_PROJECT_DIR bash "$TMP/hot/.brainforge/tripwires.sh")
has "$out" "$SYNC" "(f) no argument and no env must fall back to the script's brain"

# --- (g) session-start.sh without tripwires.sh beside it: still exit 0, other hooks still speak ---
brain bare; trip bare
rm "$TMP/bare/.brainforge/tripwires.sh"
mkdir -p "$TMP/bare/context/canon/brand"
printf -- '---\ntitle: T\nowner: TODO\nlast-reviewed: TODO\nstatus: approved\n---\n\n# T\n' > "$TMP/bare/context/canon/brand/voice.md"
out=$(CLAUDE_PROJECT_DIR="$TMP/bare" bash "$TMP/bare/.brainforge/session-start.sh") || fail "(g) must exit 0 without tripwires.sh"
has "$out" 'Context:'     "(g) pull line missing"
has "$out" 'Canon health' "(g) canon-health line missing"
hasnt "$out" "$SYNC"      "(g) no tripwires.sh, so no sync nudge"

echo "PASS tripwires"
