---
description: Check whether authored canon is still being confirmed true — flag past-review, never-reviewed, and stalled drafts.
---

Run `bash .brainforge/canon-health.sh` and relay its output.

This is the canon counterpart to `/sync-health`. That one asks whether *derived* context is
still true to its source; this one asks whether *authored* context is still true at all. Nothing
asked that before — `/drift` compares canon against derived, so a domain with no derived
counterpart (`brand`, most of `company`) had no staleness signal of any kind.

Read-only. No PR, no edits.

## What comes back, and what each finding means

| Finding | Means | Fix |
|---|---|---|
| **never reviewed** | `status: approved` with `last-reviewed` still `TODO`. The doc carries full authority on the strength of a template default — nobody has ever confirmed it. Worse than stale, and it is listed first for that reason. | Review it, then `/approve-canon`, which stamps today. |
| **past review** | `last-reviewed` is older than the doc's review cadence — the doc's own `review-cadence:`, else the shipped `biannual` (180 days). | Same. Or, if it genuinely does not rot, `review-cadence: never`. |
| **drafts** | Not yet trusted as canon. `stalled` means untouched for over 30 days, so the approve gate opened and never closed — canon nobody trusts, occupying space in the map. | Finish the `/draft-canon` → `/approve-canon` loop, or delete it. |

## Do not

- **Do not bump `last-reviewed` to silence a line.** That field means "a human confirmed this is
  still true on this date." Writing today's date without doing the confirming makes the whole
  signal worthless, and it is the one action that turns this check into theatre. Only
  `/approve-canon`, after a real review, stamps it.
- **Do not propose `review-cadence: never` to clear a report.** That is the owner's judgement
  about a specific doc, not a way to reach a clean run. Say which docs might qualify and why;
  let them decide.
- Do not edit canon here. Report, and point at `/draft-canon` for anything that needs changing.

## Closing

If a doc is past review **and** you can see from `derived/` that it is now factually wrong,
that is drift, not staleness — say so and point at `/drift`, which drafts the fix. Staleness
means nobody has checked recently; drift means somebody can see it is wrong.
