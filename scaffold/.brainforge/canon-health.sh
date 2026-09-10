#!/usr/bin/env bash
# canon-health.sh — is authored canon still being confirmed true?
#
# DESIGN.md §8 promised staleness surfaced from `last-reviewed` age as one-line nudges. Nothing
# read that field. /drift compares canon against derived and /sync-health covers derived only,
# so `brand` -- the subjective domain with no derived counterpart, the one DESIGN §4a calls the
# most dangerous to bootstrap -- had no staleness signal of any kind. A brand doc could sit
# `status: approved` and wrong for months with nothing to say so, which is exactly how a
# marketing-sourced description of a business unit contradicted that unit's own canon, under
# `status: approved`, for three weeks.
#
# Deterministic by contract: no LLM, no network. git/find/sed/awk/date only.
#
# USAGE
#   canon-health.sh                 full report   (run by /canon-health)
#   canon-health.sh --tripwire      at most ONE summary line, or silence
#
# EXIT
#   1  approved canon is past review, or was never reviewed at all
#   0  clean, or drafts only. --tripwire ALWAYS exits 0 -- a session hook must never fail.
#
# WHY A SCRIPT AND NOT A settings.json ONE-LINER, like the other two tripwires: this one needs
# frontmatter parsing and date arithmetic, and both have portability traps (BSD vs GNU `date`).
# A check whose failure is indistinguishable from "nothing to report" is the exact bug class
# this repo spent 2026-09-09 removing, so this one is testable and tested.
set -u

mode=report
canon=""
for a in "$@"; do
  case "$a" in
    --tripwire) mode=tripwire ;;
    -h|--help)  sed -n '2,24p' "$0"; exit 0 ;;
    *)          canon="$a" ;;
  esac
done

root_dir=$(git rev-parse --show-toplevel 2>/dev/null) || root_dir="$PWD"
cd "$root_dir" 2>/dev/null || exit 0

# Honour a non-default context root rather than assuming `context/`.
if [ -z "$canon" ]; then
  ctx=$(sed -n 's/^  "contextRoot": "\(.*\)",$/\1/p' .brainforge/brain-manifest.json 2>/dev/null | head -1)
  canon="${ctx:-context}/canon"
fi
[ -d "$canon" ] || exit 0

# Cutoff dates, computed once. BSD and GNU `date` disagree on relative-date syntax and neither
# is universal; if BOTH fail we say so rather than inventing an answer.
cut_at() { date -v-"$1"d +%F 2>/dev/null || date -d "$1 days ago" +%F 2>/dev/null || true; }
C90=$(cut_at 90); C180=$(cut_at 180); C365=$(cut_at 365); C30=$(cut_at 30)
if [ -z "$C180" ]; then
  [ "$mode" = tripwire ] || echo "canon-health: cannot compute dates on this system — not checked."
  exit 0
fi

# fm <file> <key> -> a top-level frontmatter value from the --- block, or empty.
fm() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1                { next }
    $0 == "---"            { exit }
    index($0, k ":") == 1  { sub("^" k ":[[:space:]]*", ""); print; exit }
  ' "$1"
}

stale=""; never=""; drafts=""; ok=0; unowned=""
n_stale=0; n_never=0; n_draft=0; n_stalled=0

while IFS= read -r f; do
  [ -n "$f" ] || continue
  status=$(fm "$f" status)
  lr=$(fm "$f" last-reviewed)
  cad=$(fm "$f" review-cadence)
  owner=$(fm "$f" owner)
  rel=${f#./}

  case "$status" in
    draft|"")
      n_draft=$((n_draft + 1))
      last=$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)
      age="unknown"; [ -n "$last" ] && age="$last"
      if [ -n "$last" ] && [ "$last" \< "$C30" ]; then
        n_stalled=$((n_stalled + 1))
        drafts="${drafts}${rel}|${age}|stalled
"
      else
        drafts="${drafts}${rel}|${age}|open
"
      fi
      continue ;;
  esac

  # An approved doc nobody has ever confirmed is worse than a stale one: it carries full
  # authority on the strength of a template default.
  case "$lr" in
    ""|TODO|todo|"<date>")
      n_never=$((n_never + 1))
      never="${never}${rel}|${owner:-no owner}
"
      continue ;;
  esac

  case "$cad" in
    never)                 ok=$((ok + 1)); continue ;;
    quarterly) cutoff=$C90;  label="quarterly" ;;
    annual)    cutoff=$C365; label="annual" ;;
    biannual)  cutoff=$C180; label="biannual" ;;
    "")        cutoff=$C180; label="biannual (default)" ;;
    *)         cutoff=$C180; label="biannual (default; unknown review-cadence \"$cad\")" ;;
  esac

  if [ "$lr" \< "$cutoff" ]; then
    n_stale=$((n_stale + 1))
    stale="${stale}${rel}|${lr}|${label}|${owner:-no owner}
"
  else
    ok=$((ok + 1))
  fi
done <<EOF
$(find "$canon" -name '*.md' ! -name 'README.md' ! -name '_index.md' 2>/dev/null | sort)
EOF

if [ "$mode" = tripwire ]; then
  # ONE line, never one per doc. The hook is a tripwire, not a report: it names the state and
  # hands off to the command, the same split the drift gate and the sync-health gate use.
  parts=""
  [ "$n_never" -gt 0 ]   && parts="$n_never never reviewed"
  [ "$n_stale" -gt 0 ]   && parts="${parts:+$parts, }$n_stale past review"
  [ "$n_stalled" -gt 0 ] && parts="${parts:+$parts, }$n_stalled draft(s) stalled"
  [ -n "$parts" ] && echo "⚠️  Canon health: $parts — run /canon-health."
  exit 0
fi

printf 'Canon health — %s\n' "$canon"
printf '  %d approved and current · %d past review · %d never reviewed · %d draft(s)\n\n' \
  "$ok" "$n_stale" "$n_never" "$n_draft"

if [ -n "$never" ]; then
  echo "✗ approved but never reviewed — carrying full authority on a template default"
  printf '%s' "$never" | awk -F'|' '{ printf "    %-44s owner: %s\n", $1, $2 }'
  echo
fi
if [ -n "$stale" ]; then
  echo "⚠ past review — the date someone last confirmed this is still true"
  printf '%s' "$stale" | awk -F'|' '{ printf "    %-44s %s  %-22s owner: %s\n", $1, $2, $3, $4 }'
  echo
fi
if [ -n "$drafts" ]; then
  echo "· drafts — not yet trusted as canon; a stalled one means the approve gate never closed"
  printf '%s' "$drafts" | awk -F'|' '{ printf "    %-44s last touched %s  %s\n", $1, $2, $3 }'
  echo
fi

if [ "$n_stale" -eq 0 ] && [ "$n_never" -eq 0 ]; then
  echo "✓ every approved canon doc is within its review cadence."
else
  echo "Re-confirm a doc by reviewing it and running /approve-canon, which stamps today's date."
  echo "A doc that genuinely does not rot can declare 'review-cadence: never' in its frontmatter."
fi
exit $(( (n_stale + n_never) > 0 ? 1 : 0 ))
