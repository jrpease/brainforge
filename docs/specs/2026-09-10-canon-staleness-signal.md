# Canon staleness signal

Status: built
Date: 2026-09-10

## Goal

`DESIGN.md` §8 promised staleness surfaced from `last-reviewed` age as one-line nudges. Nothing
ever read that field. `/drift` compares canon against derived and `/sync-health` covers derived
only, so a canon domain with **no derived counterpart** had no staleness signal of any kind —
and that is `brand`, the subjective domain DESIGN §4a singles out as the most dangerous to
bootstrap, plus most of `company`.

After this ships, a doc cannot sit `status: approved` and quietly untrue indefinitely. Three
states are visible and separable: never reviewed at all, past its review cadence, and a draft
the approve gate opened and never closed.

## Findings

**The field was already being written; nobody read it.** `/approve-canon` stamps
`last-reviewed: <today>` (`authoring/README.md` §4). Templates ship `last-reviewed: TODO`.
`context/canon/README.md` already framed the intent — *"stale-but-trusted is the enemy; revisit
on a cadence"* — so this closes a loop the docs describe rather than inventing one.

**Never-reviewed is a distinct and worse state than stale.** A doc with `status: approved` and
`last-reviewed: TODO` carries full authority on the strength of a template default. It is not
"overdue"; it was never confirmed once. It is reported first and separately.

**Drafts need a different clock.** A draft has no meaningful `last-reviewed`, so age comes from
`git log -1 --format=%cs`. A draft untouched for over 30 days means the draft→approve loop
opened and never closed — canon nobody trusts, occupying space in the map.

**This is not the disease of the always-on staleness warning (Finding 1 of the audit-hardening spec).** That warning was permanently on and could
never be true. This one fires only when it is true *and* actionable, and reviewing clears it.
The residual risk is a brain that is simply never diligent, which is why the per-doc opt-out
exists and why the tripwire is one summary line rather than one line per doc.

## Non-goals

- **Auto-bumping `last-reviewed`.** The field's entire worth is that it records a human
  re-confirming content. The command says so explicitly and refuses.
- **Judging whether canon is *correct*.** That is `/drift`, which compares against derived and
  drafts a fix. Staleness means nobody has checked recently; drift means somebody can see it is
  wrong.
- **Per-domain default cadences.** Considered and rejected (see Decisions).
- **A scheduled or autonomous reviewer.** Still deferred.

## Decisions

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Default review interval | **`biannual`, 180 days** | Two quarters. Long enough a diligent team never sees the nudge, short enough a year-old positioning doc is caught. Matches how fast brand and product principles actually move | `quarterly` (would fire most quarters on a 20-doc brain and become wallpaper); `annual` (a doc could be eleven months wrong and silent) |
| Threshold scope | **One shipped default + per-doc `review-cadence:` override** | Follows the `pipeline/README.md` Defaults precedent exactly: a default always applies, declaring a value is a refinement never a precondition | Per-domain defaults — a second table to keep in sync with an à la carte catalog |
| Stalled drafts | **Reported, as their own finding** | A draft sitting for months means the approve gate never closed. Different problem from staleness, so a different line rather than mixed in | Staleness-only, which would leave stalled drafts invisible outside the doc's own banner |
| Where the check lives | A shipped script, `.brainforge/canon-health.sh`, with two modes | Needs frontmatter parsing and date arithmetic, both with BSD/GNU traps. The other three tripwires are inline one-liners and untestable; a check whose failure is indistinguishable from "nothing to report" is the bug class this repo keeps finding | A fourth inline one-liner in `settings.json` |
| Hook output shape | **One summary line, never one per doc** | Same dumb-hook/smart-command split the drift and sync-health gates already use | Enumerating docs in the session map |

## What shipped

- `scaffold/.brainforge/canon-health.sh` — deterministic, `git`/`find`/`sed`/`awk`/`date` only.
  Bare: full report, exit 1 on past-review or never-reviewed. `--tripwire`: at most one line,
  always exit 0. Honours `contextRoot` from the manifest rather than assuming `context/`. If
  neither BSD nor GNU `date` arithmetic works it says "not checked" instead of guessing.
- `scaffold/.claude/commands/canon-health.md` — the command, with a table of what each finding
  means and an explicit refusal to hand-bump `last-reviewed` or propose `review-cadence: never`
  to reach a clean run.
- `scaffold/.claude/settings.json` — a fourth SessionStart tripwire.
- `.claude-plugin/plugin.json` — `.brainforge/canon-health.sh` added to `runtime.bump`
  explicitly (not by glob, which would sweep in the deliberately-`once` `authoring/templates/**`);
  version 0.9.1 → 0.10.0.
- Docs: `authoring/README.md` §5 ("Approval starts a clock, it does not stop one"),
  `context/canon/README.md` (the `review-cadence` contract), `.brainforge/README.md`.
- `tests/canon-health.test.sh` — the four states, the opt-out, the tighter override, the
  one-line tripwire, a non-default context root, no-canon silence, and the **actual command
  string `settings.json` ships**, run against a brain with and without the script present.

Mutation-checked: making `quarterly` behave as `biannual`, treating `TODO` as reviewed, and
having the tripwire enumerate docs each fail the suite with the expected message.

## Where it diverged

Nothing material. Two things worth recording:

**The first test fixture was wrong in a way that flattered the code.** `printf '%s'` does not
expand `\n`, so a `review-cadence: never` line landed as literal `never\n---` and the doc was
reported stale. The script's actual behaviour was correct — it fell back to the default cadence
*and said which* (`unknown review-cadence "..."`), which is the fail-safe branch working. The
fixture was rebuilt with `echo` per line.

**Report layout was double-indented** on first run because rows carried their own leading spaces
and `awk` added more. Rows now carry data only; `awk` owns the layout.
