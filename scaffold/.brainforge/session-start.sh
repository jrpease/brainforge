#!/usr/bin/env bash
# The brain's session-start hooks. `.claude/settings.json` ships one SessionStart hook that runs
# this script; the hooks themselves live here so they can be tested and upgraded as one file.
#
# On session start:
# (1) fast-forward pull the latest context so read-only consumers get current truth without
#     remembering to pull (--ff-only is safe: it no-ops on local edits/divergence rather than
#     making merge noise);
# (2) the drift gate and (3) the sync-health tripwire - cheap, dependency-free nudges to run
#     /drift and /sync-health. They live in .brainforge/tripwires.sh (see its header), which is
#     read-only and never pulls, so Brainforge Studio can run them without this script's pull.
#     Resolved beside this script, not under $CLAUDE_PROJECT_DIR; missing → silent;
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

  # (2)+(3) drift gate and sync-health tripwire, in tripwires.sh
  (
    T="$(dirname "${BASH_SOURCE[0]}")/tripwires.sh"; [ -r "$T" ] && bash "$T" "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
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
