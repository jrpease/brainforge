#!/usr/bin/env bash
# The brain's session-start hooks. `.claude/settings.json` ships one SessionStart hook that runs
# this script; the hooks themselves live here so they can be tested and upgraded as one file.
#
# On session start:
# (1) fast-forward pull the latest context so read-only consumers get current truth without
#     remembering to pull (--ff-only is safe: it no-ops on local edits/divergence rather than
#     making merge noise);
# (2) the drift gate - a dependency-free cheap check (git/cat/find/test only, no jq) that nudges
#     to run /drift when context/canon or context/derived changed since the last drift review
#     (.brainforge/last-drift-review), or when a brain with derived content has never had a
#     review;
# (3) the sync-health tripwire - a dependency-free check (grep only, no jq) that nudges to run
#     /sync-health when a source is wired but never synced (a source's slot in .sync-state.json
#     still says synced: false at the slot's own level (six-space indent, per that file's
#     formatting contract, so a synced key nested inside a fingerprint never counts), or, for
#     brains older than that flag, a populated fingerprint slot while lastFullSync is null) or a
#     derived doc still carries source: TODO. A tripwire, not a monitor: it catches the common
#     broken states cheaply; /sync-health does the full per-source accounting, and
#     cadence-staleness. Stateless - self-clears when the underlying state is fixed (unlike the
#     drift gate, which clears on acknowledgment);
# (4) the canon-health tripwire - authored canon whose `last-reviewed` is past its review
#     cadence, was never reviewed at all, or is a draft stalled over 30 days. It calls a shipped
#     script (.brainforge/canon-health.sh) because it needs frontmatter parsing and date
#     arithmetic, and both have BSD/GNU portability traps. Same dumb-hook/smart-command split:
#     ONE summary line, never one per doc, and /canon-health does the accounting. Stateless,
#     self-clears on resolution.
# Then a legacy detector: if .claude/settings.json still carries the old inline hooks (from
# before they moved here), say so once, because both copies would print every nudge twice.
#
# All of it fails safe: a missing/bad file or a failed command is silent, never an error. Each
# hook runs in its own subshell so one failure cannot silence the others, and the script always
# exits 0.
#
# The body sits inside `main`, and the last line is `main "$@"; exit 0`. Bash reads a script as
# it runs, and hook 1 (git pull) can rewrite this very file mid-run. The function makes bash
# parse the whole body before anything executes, and the `exit` on the same line stops bash
# from reading on into whatever a longer rewritten file has after that point. Keep both.

main() {
  CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
  export CLAUDE_PROJECT_DIR

  # (1) pull
  (
    git -C "$CLAUDE_PROJECT_DIR" pull --ff-only --quiet 2>/dev/null && echo 'Context: pulled latest.' || echo 'Context: could not fast-forward (local changes or offline) — using current copy.'
  )

  # (2) drift gate
  (
    WM="$CLAUDE_PROJECT_DIR/.brainforge/last-drift-review"; if [ -e "$WM" ] && [ ! -s "$WM" ]; then echo '⚠️  Drift watermark is empty — run /drift to check canon vs. reality.'; elif [ -s "$WM" ]; then SHA="$(cat "$WM")"; if ! git -C "$CLAUDE_PROJECT_DIR" cat-file -e "$SHA^{commit}" 2>/dev/null; then echo '⚠️  Drift watermark names a commit this clone does not have (squash-merged, rebased, or pruned) — run /drift to re-establish it.'; elif ! git -C "$CLAUDE_PROJECT_DIR" diff --quiet "$SHA" HEAD -- context/canon context/derived 2>/dev/null; then echo '⚠️  Context changed since last drift review — run /drift to check canon vs. reality.'; fi; elif [ ! -e "$WM" ] && [ -n "$(find "$CLAUDE_PROJECT_DIR/context/derived" -name '*.md' ! -name 'README.md' ! -name '_index.md' -print -quit 2>/dev/null)" ]; then echo '⚠️  Context has never had a drift review — run /drift to check canon vs. reality.'; fi
  )

  # (3) sync-health tripwire
  (
    D="$CLAUDE_PROJECT_DIR"; S="$D/.sync-state.json"; N=""; if [ -d "$D/context/derived" ] && grep -rqE '^source:[[:space:]]*TODO' "$D/context/derived" 2>/dev/null; then N=1; fi; if [ -f "$S" ] && grep -qE '"lastFullSync":[[:space:]]*null' "$S" 2>/dev/null && grep -qE '"[a-zA-Z0-9_-]+":[[:space:]]*\{$' "$S" 2>/dev/null; then N=1; fi; if [ -f "$S" ] && grep -qE '^      "synced":[[:space:]]*false' "$S" 2>/dev/null; then N=1; fi; if [ -n "$N" ]; then echo '⚠️  Sync health: a source is unsynced or still has a TODO — run /sync-health.'; fi
  )

  # (4) canon-health tripwire
  (
    cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && [ -r .brainforge/canon-health.sh ] && bash .brainforge/canon-health.sh --tripwire 2>/dev/null || true
  )

  # legacy detector: the old inline hooks are still in settings.json
  (
    if grep -q 'last-drift-review' "$CLAUDE_PROJECT_DIR/.claude/settings.json" 2>/dev/null; then echo '⚠️  .claude/settings.json still has the old inline session hooks — delete them; .brainforge/session-start.sh runs them now.'; fi
  )

  return 0
}
main "$@"; exit 0
