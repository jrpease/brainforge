# Brainforge design system, synced between Figma and code

Status: spec (v0 tokens are built under the Studio plan; Figma formalizing is planned separately)
Reviewed: 2026-10-15 — ready to plan
Date: 2026-10-14

## Goal

The Brainforge brand has a palette, fonts and motion, but they live only as a Tailwind `@theme` in
the marketing site, with no Figma file, no token files, no type scale and no light mode. This spec
sets up one Brainforge design system, built with the throughline plugin, that is explored live in
code and formalized in Figma once it is liked. Brainforge Studio
(`docs/specs/2026-10-14-admin-studio.md`) is its first user.

Split out of the Studio spec on 2026-10-14 at review, so the two can be planned on their own clocks.

## Non-goals

- **Moving the brand site onto the system.** The system is the brand's, and the site could adopt it
  later; this spec does not do that.
- **Chromatic.** Storybook arrives with Studio v1; visual-regression CI does not.
- **A code → Figma sync.** throughline syncs one way, Figma to code. Formalizing a value into Figma
  is a manual authoring run with throughline's token skills, not a reverse sync.
- **The theme switch.** Following the system setting and remembering a toggle is app behaviour; the
  Studio spec owns it. This system only defines the modes.

## Decisions

Settled in the Studio grilling on 2026-10-14. Jordan accepted the stated recommendation unless the
row says otherwise. Rows marked *(review)* came from the 2026-10-14 review, whose recommended fixes
Jordan accepted on 2026-10-15. Rows marked *(standing)* were open questions the Studio v0 plan
needed answered; they take the recommendation under Jordan's standing instruction for this work
("take your recommendations when you have a question; only pull me in for an important P0"), given
2026-10-14. Either can be reopened.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Whose | One **Brainforge** design system (the brand's palette, type and motion), used by Studio now | The palette already is the brand | A Studio-only system |
| Tooling | Jordan's call: set up a synced Figma ↔ code design system with the **throughline** plugin. Update throughline to its latest release first (0.29.0 on 2026-10-14; the cached copy is 0.25.0) | — (Jordan's direction); four minor versions of drift is too many to plan against | Hand-maintained tokens with no Figma side |
| Where tokens live | Inside `studio/` for now: DTCG sources in `studio/tokens/`, generated CSS in `studio/src/styles/tokens.css` through throughline's `vanilla-css` adapter | A monorepo for one app is all cost; tokens can move out if the brand site adopts them | throughline's default pnpm + Turborepo `packages/tokens/` |
| Running throughline off its default layout *(review)* | Run throughline from `studio/`, so `design-system.json` and its `design-system/` folder live there. Decline its monorepo conversion and its `design-system-audit` hand-off. Call its pipeline scripts with Studio's paths (`--system`/`--out`, `--source`/`--output`, Style Dictionary `buildPath`) wherever the skill's prose names `packages/tokens/` | throughline classifies a folder with a `package.json` and no `turbo.json` as an existing repo and pushes a monorepo; its scripts are path-agnostic, only its prose is not | Converting brainforge to a monorepo |
| Token names *(review)* | Throughline's two-tier naming from day one: primitives (the brand's values, e.g. a `void` ramp) and semantic tokens (`--color-bg-default`, `--color-text-primary`) that point at them. Studio code uses only semantic names, never a brand primitive | The draft can only override the generated file if both use the same names; naming them that way now means formalizing never forces a rename across Studio | Studio code written against `--color-void`, `--color-canon` |
| Direction | Jordan's call: **explore in code, then formalize in Figma.** Build it in code, adjust colours, type and components live, and institutionalize what we like in Figma | See it live before formalizing it | Designing in Figma first |
| Modes | Light **and** dark, as two modes of the same variables. Dark is the default (the bare `:root`); light is `[data-theme="light"]`. throughline does not fix which mode is the base, so this holds only if the Figma semantic collection's default mode is Dark and the Style Dictionary config builds the dark set into `:root`; both are set at the first formalize. The brand's dark "void" stays the reference | Jordan wants both; dark-as-default from the *(review)* fixes | Dark only |
| Type, spacing, radius | A small fixed type scale (about six steps), plus spacing and radius tokens. The marketing site's fluid `clamp()` sizes stay where they are | An admin app is dense; the brand has fonts but no scale | Reusing the site's fluid sizes |
| How far, when | Tokens, type and spacing before Studio v0's screens. Figma components and Storybook with Studio v1, when the Inbox and canon editor bring the first reusable components. No Chromatic | Components worth drawing do not exist until v1 | Drawing components before they exist in code |
| Explore-then-formalize mechanism *(standing)* | Two layers. `tokens.css` is generated from Figma and never hand-edited; `tokens.draft.css` is hand-edited and loads after it, so it overrides. Formalizing a value is an authoring run (`token-builder` in import mode, which proposes extra ramps and roles; accept or trim them there), then a sync down, then the value is deleted from the draft. Components the same way: React first, drawn in Figma with throughline's component skills once settled. The draft is the source of truth until a value is formalized; then Figma is. At the start the draft holds everything, in the two-tier names, and `tokens.css` is a hand-created empty file, because throughline's sync refuses to run until Figma has semantic tokens. Studio's CI warns, never fails, while the draft is non-empty (Studio's "CI lane" row gains that step) | Live exploration without breaking throughline's one-way, never-hand-edit rule | Hand-editing generated tokens; a code → Figma sync |
| The stale colour *(standing)* | `stale #ff5c5c` stays "the one alarm accent, only for drifted facts" in both modes; Studio's Health is the main place it appears | Keeps the brand's one rule about alarm | Using it as a general error or destructive colour |

## Open questions

- **The light palette's values.** Decided that it exists, not what it is. Designed live in code, per
  the direction row. Not a blocker for planning.
- **Who pairs the Figma bridge.** throughline needs the Figma desktop app with its bridge plugin
  paired. That is a step only Jordan can do, at the point the plan first formalizes into Figma. Not a
  decision; a dependency to schedule.

## Facts this rests on (checked 2026-10-14)

- throughline (cached 0.25.0; source 0.29.0 at `~/Dev/throughline`) syncs Figma → DTCG JSON → Style
  Dictionary → an adapter; records the Figma file key in `design-system.json` (`figma.fileKey`);
  needs the Figma desktop app with the figma-console bridge plugin paired. Its curated `vanilla-css`
  adapter emits `:root` and `[data-theme]` CSS variables; nothing in throughline emits or watches
  `prefers-color-scheme`. Its repository builder defaults to pnpm + Turborepo with `packages/tokens`,
  and `token-sync-layer`'s prose names `packages/tokens/` throughout, while its scripts take paths as
  arguments. `token-builder` has an import mode that writes given values into Figma variables, with a
  completeness pass on top. The marketplace clone is also at 0.25.0, so updating means refreshing
  the marketplace first.
- Two Figma modes per collection need a paid plan (the free tier allows one). Jordan said on
  2026-10-14 that his plan supports multi-mode variables.
- `brainforge-brand` has no Figma file or token files; its palette is a Tailwind 4 `@theme` in
  `apps/site/app/globals.css:7-41`: void `#05070a`/`#080b11`/`#0c111a`; canon
  `#e8b57a`/`#c98a4b`/`#7a5f43`; derived `#37e5ff`/`#0aa4c4`/`#2a6b78`; seam `#d8ffe9`; stale
  `#ff5c5c`; bone `#eaf2f5`, slate `#7c8a94`/`#727e89`, line `#18222c`; fonts Space Grotesk,
  Instrument Serif, JetBrains Mono; easing tokens at lines 40-41.
