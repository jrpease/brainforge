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
- Density target, Health: 30–60 interactive targets per megapixel.
- Spacing steps used on Health: 4 / 8 / 12 / 16 / 24.

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
| refresh | content present, reloading in place | input + route delayed |
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
| 820ms | 0.02 | 8 | 3 | 0.35 |

Against the reveal IQR (350–650ms, 0–0.07, 3–10, 1–2, 0.03–0.18): outside on duration, groups and
coverage; inside on travel and participants. Floor met (groups ≥ 2).

Reduced motion: no travel, no stagger; each row's status changes in place, all at once.

## Killed comp

**Killed: A · Ledger** (Jordan, 2026-10-15). Kept: **B · Seam**, with its narrow-width command fix.

A lost on density: 11 vs 13 action items above the fold at 1440 (7 vs 9 at 1024), and a 1684px vs
1288px page, for one ranked list whose only measured win was 0 vs 3 truncated commands at 1024, which
B fixes in layout. Measured with `design/.harness/fold2.mjs` on the `dense` state.

The killed comp is kept at `design/comps/a-ledger/` and still renders at `?dir=a`.

Recommendation history, for the record: A was first recommended on the claim that it showed more per
screen. Measuring showed the opposite; Jordan picked again on the corrected numbers.
