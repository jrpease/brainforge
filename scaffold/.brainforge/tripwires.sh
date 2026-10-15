#!/usr/bin/env bash
# tripwires.sh — the drift-gate and sync-health nudges, with nothing else attached.
#
# These two checks used to live inline in session-start.sh. That script starts with a
# `git pull`, so anything that wanted the nudges without pulling the brain (Brainforge Studio's
# Health panel, which must never write to the brain) had nowhere to get them. They live here
# now; session-start.sh calls this script after its pull, so a session's output is unchanged.
#
# (2) the drift gate - nudges to run /drift when context/canon or context/derived changed since
#     the last drift review (.brainforge/last-drift-review), or when a brain with derived
#     content has never had a review. Clears on acknowledgment (/drift re-stamps).
# (3) the sync-health tripwire - nudges to run /sync-health when a source is wired but never
#     synced (a slot in .sync-state.json still says synced: false at the slot's own level,
#     six-space indent per that file's formatting contract; or, for brains older than that flag,
#     a populated slot while lastFullSync is null) or a derived doc still carries source: TODO.
#     A tripwire, not a monitor: /sync-health does the full accounting and cadence-staleness.
#     Stateless; self-clears when the state is fixed.
#
# Read-only by contract: git/cat/find/grep/test only. No network, no writes, no jq.
#
# USAGE
#   tripwires.sh [brain-dir]    brain-dir defaults to $CLAUDE_PROJECT_DIR, else this script's
#                               brain (the parent of .brainforge/). Keep this argument stable:
#                               after a pull, an older session-start.sh can run a newer copy.
#
# OUTPUT  at most one line per tripwire, or silence.
# EXIT    always 0. A non-zero exit means the script itself broke, never a finding.

main() {
  BRAIN="${1:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}}"

  # (2) drift gate
  (
    WM="$BRAIN/.brainforge/last-drift-review"; if [ -e "$WM" ] && [ ! -s "$WM" ]; then echo '⚠️  Drift watermark is empty — run /drift to check canon vs. reality.'; elif [ -s "$WM" ]; then SHA="$(cat "$WM")"; if ! git -C "$BRAIN" cat-file -e "$SHA^{commit}" 2>/dev/null; then echo '⚠️  Drift watermark names a commit this clone does not have (squash-merged, rebased, or pruned) — run /drift to re-establish it.'; elif ! git -C "$BRAIN" diff --quiet "$SHA" HEAD -- context/canon context/derived 2>/dev/null; then echo '⚠️  Context changed since last drift review — run /drift to check canon vs. reality.'; fi; elif [ ! -e "$WM" ] && [ -n "$(find "$BRAIN/context/derived" -name '*.md' ! -name 'README.md' ! -name '_index.md' -print -quit 2>/dev/null)" ]; then echo '⚠️  Context has never had a drift review — run /drift to check canon vs. reality.'; fi
  )

  # (3) sync-health tripwire
  (
    D="$BRAIN"; S="$D/.sync-state.json"; N=""; if [ -d "$D/context/derived" ] && grep -rqE '^source:[[:space:]]*TODO' "$D/context/derived" 2>/dev/null; then N=1; fi; if [ -f "$S" ] && grep -qE '"lastFullSync":[[:space:]]*null' "$S" 2>/dev/null && grep -qE '"[a-zA-Z0-9_-]+":[[:space:]]*\{$' "$S" 2>/dev/null; then N=1; fi; if [ -f "$S" ] && grep -qE '^      "synced":[[:space:]]*false' "$S" 2>/dev/null; then N=1; fi; if [ -n "$N" ]; then echo '⚠️  Sync health: a source is unsynced or still has a TODO — run /sync-health.'; fi
  )

  return 0
}
main "$@"; exit 0
