# Brainforge Studio v0 — SCREENS.md

The `product-design` run's output document. Values, not reasons. The design and its reasons live in
`docs/specs/2026-10-14-admin-studio.md` and `docs/specs/2026-10-14-brainforge-design-system.md`.

## Intake (confirmed by Jordan, 2026-10-15)

- **Flow:** Setup check → Health → Brain browser → Sources list.
- **Surfaces:** desktop web only, 1440 wide, floor 1024 wide. Phones are not a target.
- **Hard screen:** Health.

## System mode

**Mode 1, spine authored in this run.** Evidence: no `design-system.json` in `studio/`, no component
library in `package.json`, no token layer before this run. The spine's tokens live in
`src/styles/tokens.draft.css` (two tiers; components bind semantic names only). The Figma side is the
design-system spec's job and comes later.

## Canon targets

- **Stripe — payments table.** Hierarchy at 2.33× contrast on a 14px body, carried by weight and
  colour. Borrowed for: the Health rows — rank by weight and status colour, never by size.
- **Slack — channel view.** A complete product on a 5-step spacing scale. Borrowed for: holding
  Health to five spacing steps.
- **Acorns — portfolio summary.** Calm earned by removing controls (12.7 targets/MP, 7 colours).
  Borrowed for: the all-clear state, which shows almost nothing.

Desktop caveat: the canon's motion numbers are iOS only; the signature moment's amplitude is the
weaker claim on this surface.

## Precedent (Mobbin, web; saved under `design/precedent/`)

- `openai-service-health.webp` — [Mobbin](https://mobbin.com/screens/d605f83d-3869-4ecc-8874-b913e09e2930): one status sentence at the top, then collapsible rows; the verdict before the detail.
- `supabase-security-advisor.webp` — [Mobbin](https://mobbin.com/screens/e3ac7f2c-bdd0-42a4-ac13-76fb893fd06d): severity tabs with counts, a Refresh beside the list, and a footer naming which tool produced the findings.
- `vanta-tests.webp` — [Mobbin](https://mobbin.com/screens/7b3e98c2-b1fd-4c66-b4f4-51fbbb0a346f): an OK count against a "needs attention" count split by cause.
- `semrush-site-audit.webp` — [Mobbin](https://mobbin.com/screens/0f5eb2f2-aa33-4170-998c-0754c86f0b82): issues grouped by severity, each with a "how to fix" beside it, and a rerun action in the header.
- `aws-service-health.webp` — [Mobbin](https://mobbin.com/screens/9291c01f-0f1f-44ed-a429-452d1010f4cb): "No recent issues · Updated less than 1 minute ago" as the all-clear.
- `betterstack-heartbeat.webp` — [Mobbin](https://mobbin.com/screens/7bb32a8e-652b-41ff-a3b9-8f43d3260d9f): a dark dense status surface with "pending / waiting" as a first-class value.
- `supabase-edge-function.webp` — [Mobbin](https://mobbin.com/screens/1d51f335-116b-4d52-89cb-49dbf67c7caf): status codes as small mono chips inside a dense row.
- `hotjar-no-results.webp` — [Mobbin](https://mobbin.com/screens/f0a33f18-6564-4d92-b1e6-7622a2f0e7ab): empty states inside their tile, not as separate pages.

## Type and density

- Family: **dense**. Body 14px. Size set 12 / 14 / 16 / 20 / 28. Weights 400 and 600 (500 for labels).
  Contrast 28/14 = 2.0×.
- Density target, Health: declared 30–60 interactive targets per megapixel before build; measured
  14/MP on `dense` at 1440 (28/MP counting each chip's copy affordance), critic round 1. Below the
  declaration because each canon item carries exactly one action; accepted as the task's density.
- Spacing steps used on Health: 4 / 8 / 12 / 16 / 24.

## Spine

- Tokens: `src/styles/tokens.draft.css` (draft layer; `tokens.css` is the empty generated layer).
- Palette in use, by role (dark / light): bg-default void / paper · bg-subtle · bg-raised ·
  text-primary bone / void-3 · text-secondary slate / ink-slate · text-muted slate-dim / ink-muted ·
  border line / paper-line · accent-canon · accent-derived · accent-seam · status-stale (drift and
  out-of-date facts only) · status-warning amber · status-error violet · status-success seam ·
  status-info (hollow dot). All text pairs ≥ 4.5:1, measured.
- Components: `Dot` (status, 5 severities) · `Command` (mono command chip, copies on click) ·
  `ThemeToggle` · `Skeleton` · `ErrorNotice` · Health rows (`sm-card`, `sm-src`) · counter band.
- Templates: **dashboard** (Health: verdict, counter band, two columns with the seam) ·
  **list + detail** (Brain: domain tree, document) · **list** (Sources, Setup). Empty, error and
  unavailable states render inside each template, never as their own page.

## Chrome

One pinned 48px bar: wordmark, screen nav (current screen marked), brain name and path (path hidden
below 1180px), theme toggle. Setup appears in the nav only while something is missing, with a dot.
Chrome is quieter than content: 14px/500 nav, muted path.

## Interaction manifest

| moment | type | trigger | surface |
|---|---|---|---|
| sources-resolve (signature) | reveal | click "Check sources now" | 1440, 1024 |
| content arrives after skeleton | reveal | page load | all |
| command copied | feedback | click a command chip: 200ms press-and-settle, border and label turn seam ("copy" → "copied", held 1.2s) | all |

Other budgets: content arrival 220ms ease-out, 4px; copy feedback 200ms ease-out.

## Performance and accessibility budgets

LCP ≤ 2500ms · CLS ≤ 0.1 · INP ≤ 200ms · axe 0 critical/serious, every focus ring visible, every
control keyboard-reachable, both themes, every state.

Product copy voice: Brainforge has no product voice guide (`VOICE.md` or brand copy rules), so
Studio's copy falls back to Jordan's voice: short, plain, direct.

## State inventory — Health (desktop 1440 and 1024; dark and light)

| state | what it shows | force |
|---|---|---|
| initial-load | skeleton of the arriving layout | route: `/api/health` delayed |
| all-clear | canon current, no tripwires, sources not yet checked | route |
| first-run | a brand-new brain: canon all drafts, no sources.json | route |
| single-item | one stale canon doc, nothing else | route |
| dense | stale, never-reviewed and stalled canon, both tripwires, 12 sources mixed | route |
| overflow | long paths, a long gate reason, a 5-digit count | route |
| tripwires | drift and sync nudges firing, canon clean | route |
| gates-running | "Check sources now" in progress | input + route delayed |
| gates-mixed | changed / unchanged / never / not-checked / blocked | input + route |
| gate-error | a gate exited 1 (no python3) | input + route |
| degraded-older-brain | tripwires and manifest unavailable; canon still shown | route |
| canon-error | canon-health.sh broke (exit 2) | route |
| refresh | content present, reloading in place | input + second request held (`shoot-refresh.mjs`; the state harness cannot hold only the second request) |
| server-down | the API is unreachable | route: status 0 / abort |
| unauthorized | opened without the launch link's token | route: 401 |
| no-results | **does not apply**: Health has no search or filter | — |
| permission-denied | covered by `unauthorized`; GitHub permissions are not read in v0 | — |

Loading thresholds: nothing under 100ms; in-place on the pressed control 100ms–1s; skeleton over 1s;
gates over 10s show which gate is still running.

## Signature moment (declared before build)

**What it marks:** "Check sources now" resolving — the brain's derived side being checked against
reality, one source at a time. Type: **reveal**.

| duration | travel | participants | groups | coverage |
|---|---|---|---|---|
| 820ms | 0.50 | 8 | 3 | 0.35 |

Against the reveal IQR (350–650ms, 0–0.07, 3–10, 1–2, 0.03–0.18): outside on duration, travel,
groups and coverage; inside on participants. Floor met (groups ≥ 2).

Travel is large on purpose: the seam-coloured line sweeps the whole Derived column, because the moment
means "every source was just checked". First declared at 0.02, which described the rows and missed the
line; corrected after measuring (821ms, travel 0.51 at 1440, 13 parts, 3 groups, coverage 0.35).

Reduced motion: no travel, no stagger; each row's status changes in place, all at once.

## Killed comp

**Killed: A · Ledger** (Jordan, 2026-10-15). Kept: **B · Seam**, with its narrow-width command fix.

A lost on density: 11 vs 13 action items above the fold at 1440 (7 vs 9 at 1024), and a 1684px vs
1288px page, for one ranked list whose only measured win was 0 vs 3 truncated commands at 1024, which
B fixes in layout. Measured with `design/.harness/fold2.mjs` on the `dense` state.

The killed comp is kept at `design/comps/a-ledger/` and still renders at `?dir=a`.

Recommendation history, for the record: A was first recommended on the claim that it showed more per
screen. Measuring showed the opposite; Jordan picked again on the corrected numbers.

## Critic rounds

**Round 1 (REVISE).** Major: 1024 canon rows truncated paths and wrapped titles — the light 1024
shots in that pack predated the narrow-layout fix (stale capture), but the finding stood until
reshot. Minors fixed in round 2: chip left edges aligned into one action column per side; Brain
document title now outranks the page title; seam line no longer cuts through a full-width band;
Setup status word sits with its item; content now arrives with a 220ms reveal instead of a cut.
Density recorded above. Not evidenced in round 1 and supplied for round 2: dark and 1024 and
reduced-motion recordings of the signature.

**Round 2 (REVISE-and-recapture, the cap).** Rubric items 1–4, 6 and 7 passed (canon rank: no named
target or precedent places above on a visible axis; signature "a cold viewer can name it"; 0 of 12
tells). All round-1 findings confirmed resolved. Blocking was evidence, not design: `refresh` had no
cell; `dense` and `gates-mixed` rendered identically (the manifest clicked the gates in both); two
declared moments were never captured. Fixed after round 2, not re-judged by a critic (the cap is two
rounds): `refresh` shot (40 states now); `dense` no longer runs the gates; all 3 moments captured
(6/6; "command copied" now has a 200ms feedback, it was an instant swap with nothing to record);
sweep line held inside its column; counter numerals use the caption's zero. Not changed: three
page-title sizes across screens (Health's is the verdict sentence); the skeleton-to-content gap of
1–2 frames; overflow rows truncating their chips (the state's job).

**Performance floor, accepted by Jordan 2026-10-15.** The long-frames rule (>16.7ms) reads 26–30% on
Health and 37–40% on a static blank page on this machine, with no frame over 16.8ms; the jank control
reads 57% with 33.5ms frames. Recorded as not evidenced as jank, not as a pass. Jordan agreed at PR #17
to ship past the failed floor.
