# Company as a sixth catalog domain

Status: built
Date: 2026-09-07

## Goal

`context/canon/company/` holds constitutional material — mission, values, operating
principles, org design — that fits none of the five catalog domains, so it declares no
`kinds:` and routes to nothing. This adds `company/` to the catalog with two kinds and two
intents, so that material is reachable. Same failure class as the pricing gap
([`2026-09-07-unroutable-brain-content.md`](2026-09-07-unroutable-brain-content.md)), one
level up: that was a missing kind under an existing domain, this is a missing domain.

## Non-goals

- **Splitting `company/` into subdomains.** Kinds are declared per domain, so both new kinds
  select the whole folder. Finer granularity is a brain-side structural change, not a
  vocabulary one.
- **Wiring the company domain into planning questions.** See the North Star decision below.

## Decisions

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Is `company/` a kind under an existing domain, or a domain of its own? | A sixth catalog domain | The material is constitutional, not product/brand/design/eng/analytics. It grew organically for exactly that reason | Folding mission and org design under `product/` |
| Where does the North Star sort? | Into `company-principles`; no separate `north-star` kind | DESIGN.md §4 already assigns "metric / north-star definitions" to `analytics/`, covered by the existing `metric-definitions` kind. A second word for the same phrase in a closed vocabulary gives a brain owner no way to tell which to stamp — the silent-misrouting setup this whole line of work exists to kill | A North Star question routing through the planning intent alongside `product-roadmap` |
| How many new kinds? | Two: `company-principles`, `org-design` | Each appears in exactly one intent, and in a different one from the other. A kind that shares every intent with another kind is a redundant word; a kind no intent points at is a dead one | A three-kind vocabulary (21 → 24) |
| The `acme-brain` fixture manifest was schema 1 while `gen-manifest.sh` emits schema 2 | Regenerate it in the same change | The band-gate fix shipped in synapse 0.5.0 tells the reader to compare `indexTokens` against `tokens`. Without the field, no eval case could exercise the behaviour the plugin ships | Leaving it for its own commit, which was the original plan |
| Which of the memo's "four pieces" is the real scope? | All four, plus the catalog itself | The memo listed the four files the *pricing* fix touched. Pricing added a kind to a domain that already existed. A new domain also needs the §4 catalog table, the §1 status ladder, and the `/forge` menu in `context/canon/README.md`, or §1a describes a domain `/forge` never offers | Shipping §1a alone and leaving the catalog inconsistent with it |

## Open questions

- **Should `company/` be deferred in the `/forge` menu the way `brand` is?** It is
  authored-only and carries the same blank-page tax. §2 currently names only `brand`. Not
  raised, not changed. Unresolved.

## What shipped

- `synapse/routing/intents.json` — two intents, one kind each
- `synapse/routing/README.md` — vocabulary list, 21 → 23
- `scaffold/setup/README.md` — §1a catalog row; §1 ladder five → six domains
- `scaffold/context/canon/README.md` — `company/` in the à la carte catalog (a `runtime.once`
  path: new brains get it, existing brains do not)
- `DESIGN.md` — §4 catalog row and §10 kinds row
- `ROADMAP.md` — kinds count
- `evals/fixtures/acme-brain/context/canon/company/` — `_index.md`, `principles.md`, `org.md`
- `synapse/evals/routing/company-mission/`, `synapse/evals/routing/org-ownership/` — one
  regression case per new intent
- `evals/fixtures/acme-brain/.brainforge/brain-manifest.json` — regenerated to schema 2. No
  domain's band changed; every domain gains `docTokens` and `indexTokens`, and `tokens`
  becomes the honest total. Generated in an isolated copy with an unborn HEAD and no remote —
  running the generator in place would stamp this repo's remote into the fixture
- both `plugin.json` versions — brainforge 0.7.0 → 0.8.0, synapse 0.5.0 → 0.6.0

## Where it diverged

The memo recommended a separate `north-star` kind and flagged it as a genuine call. It was
put to Jordan with the §4 collision that the memo had not accounted for, and the call went
the other way.

The fixture-manifest regeneration was written up as a separate follow-up and then pulled into
this change at Jordan's request. Nothing else diverged.

## Plan

Built as written. Verification, for the record:

- `tests/*.test.sh` — 7/7 pass
- Intent → domain intersection simulated against the fixture manifest, before and after:
  every pre-existing intent selects exactly the domains it selected before; both new intents
  select `context/canon/company` and nothing else; the fixture has no unroutable kinds
- `bash synapse/evals/routing-smoke.sh` — 8/9 pass on the final tree. `company-mission` and
  `org-ownership` both pass. The one failure is `launch-email`/`no-tracker-reads`, the stable
  unowned failure recorded in the other spec. `build-prototype` failed a *different* grader on
  each of two consecutive runs earlier in this change with no code change between them, then
  passed clean on the final run — the flakiness already recorded there, not a regression
- `claude plugin eval` did NOT run — still gated behind org-level early access
