# Adapters honour `into:`

Status: built
Date: 2026-09-14

## Goal

Every `sources.json` entry declares `into:`. `ADAPTER-TEMPLATE.md` put it in the canonical entry
shape and `pipeline/README.md` resolves `acceptedSize[].doc` relative to it, so it read as the
field that controls where a sync writes. No adapter read it. Each one hardcoded its own folder
and stamped its own `kinds:`, and where the entry and the adapter disagreed, the adapter won.

A subscriber brain moved four product-unit docs out of `context/derived/repos/` into a new
`context/derived/units/` domain and repointed `into:`. That was the fix for a real routing
defect: unit questions were resolving to brand canon instead of the owning team's own docs. The
next `/sync github` would have written them back to `repos/` and stamped `kinds:
[repo-summaries]`, emptying the new domain and regressing routing. It would do that on a cadence,
silently, and the only symptom would be a confident wrong answer.

After this ships, a sync writes where the entry says or does not run, and routing belongs to
the domain.

## Findings

**All five adapters had it, not just github.** The report's line anchors (github 108/116, ga
97/110, monday 89/106, website 35/43, figma 52/109) were all confirmed. The Shopify example had
it too, at five lines, and it is the model `/add-adapter` copies.

**`kinds:` stamping is the same bug one layer down.** An adapter stamping kinds decides routing
for a domain it does not own. `/sync` already had the right mechanism for a domain with no kinds:
propose a classification and have a human confirm it. Adapters bypassed it.

**The entry shape had more inert fields than `$note`.** Per-field audit (Decisions table has the
outcome):

| Field | Consumer before | After |
|---|---|---|
| `id` | `/sync <type> <id>` scoping, state slot key | unchanged |
| `label` | nothing | `/sync-health` source column, sync PR summary |
| locator (`fileKey`, `boardId`, `propertyId`, `sitemap`, `shopDomain`) | adapter §1 gate | unchanged |
| `localClone`, `branch` | implicit `<clone>`/`<branch>` in github.md; `/sync-health` | named explicitly in github §0 |
| `remote` | nothing | github §1 checks the clone's origin matches it, stops on mismatch |
| figma `url` | nothing (`fileKey` is the locator) | removed from the example |
| websites `url` | nothing | default for `sitemap` when absent (`<url>/sitemap.xml`) |
| `extract` | figma §1 only | figma, ga §2, shopify §2; removed from monday (nothing to choose between) |
| `summarize` | github §0b, `/sync-health` | unchanged (see Open questions) |
| `into` | nothing | every adapter §0 + emit step; `sync-contract.sh` |
| `enabled` | `/sync`, `sync-all`, `/sync-health` | unchanged |
| `cadence` | `/sync-health` | unchanged |
| `acceptedSize` | `/sync` rule 6 | unchanged |
| `$note` | nothing | removed from template, example, `$examples` |
| shopify `storefrontDomain` | nothing | removed from the example |

## Non-goals

- **Modifying any consumer brain.** They pick this up through `/brainforge:upgrade`.
- **Migrating existing `$note` fields out of brains.** `sources.json` is a `once` path. A leftover
  `$note` is harmless JSON that nothing reads.
- **Reconciling `summarize` semantics.** See Open questions.

## Decisions

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Destination | The entry's `into:`, with the conventional folder named only as an example | The report's fix 1. The entry is brain-owned; the adapter is re-emitted on every upgrade | Adapter-owned folders |
| Missing `into:` on an enabled entry | **Stop, sync nothing**. Disabled entries are skipped; enabling one re-runs the check | The report's fix 3. A fallback to the historical folder is the exact path that undoes a move | Per-source skip-and-continue (quiet in a scheduled `sync-all` PR); a default folder |
| `into:` outside `<contextRoot>/derived/`, or not ending in `/` | Fail | Derived output written into canon would be overwritten canon. `contextRoot` resolves like `gen-manifest.sh` so a moved root still works | Unvalidated paths |
| Kinds and the index | Adapters never write `kinds:`. On an existing `_index.md` they update only their own rows and `last-synced`; `title:`, `source:`, `kinds:` stay as found, since several sources can share a destination. A missing one is created with provenance and `title:`, no `kinds:`, so the manifest lists it unclassified | The report's fix 2. The unclassified path already routes through `/sync`'s human confirmation, and the adapter may name its usual kind as that proposal | Adapter stamps; merging adapter kinds into existing ones |
| Enforcement | `.brainforge/sync-contract.sh`, run as `/sync` step 0 and `sync-all` step 0, exits 1 on any violation | "Adapters must honour `into:`" is mechanically checkable, like `coverage.sh`. It also catches a custom adapter from `/add-adapter` reintroducing either bug | Prose only |
| Check dependency | `python3`, fail closed if absent | Parsing arbitrary `sources.json` with awk is fragile, and `/upgrade` already needs python3 on a maintainer machine | A grep parser that goes quiet on unusual formatting |
| Where the check lives | In the brain (a bump file), not synapse | It needs no plugin-side table, unlike `coverage.sh`'s dependence on `intents.json` | Synapse-side |
| Inert fields | Wire where a real consumer exists, remove where none does | A field that looks authoritative and does nothing is worse than no field | Keeping them "for documentation" |
| Figma entries sharing a `fileKey` | Gate once, extract every entry sharing it before writing the new `version` | One file feeding several domains now means several entries, and they share a state slot | Re-keying figma state by `id` |
| Versions | brainforge 0.11.0 → 0.12.0; synapse 0.7.2 → 0.7.3 | `pipeline/**` and a new bump file; SKILL.md said "every adapter emits" a kind, which is no longer true | |

## What shipped

- `scaffold/pipeline/README.md` § Where a sync writes: the rule, stated once.
- All five adapters and `examples/shopify.md`: `into:` in §0, `<into>` in every emit path, size
  tables relative to `<into>`, no `kinds:` stamps, fail-closed line.
- `ADAPTER-TEMPLATE.md`: same, plus the field-to-consumer table and the rule that a field needs
  the step that reads it.
- `scaffold/.brainforge/sync-contract.sh` + `tests/sync-contract.test.sh`. Against the pre-fix
  playbooks it reports 23 violations, covering every line the report named.
- `/sync`, `sync-all`, `/add-source`, `/add-adapter`, `/sync-health` wired to the above.
- Stale "every adapter mandates a kind" claims corrected in synapse and `ROADMAP.md`.

## Open questions

- **`summarize` has two vocabularies.** The `repos` example uses topics (`routes`, `components`),
  while github §0b intersects it with path globs (`docs/**`) from `.brainforge-source.yml`. An
  intersection of topics with globs is undefined. It is consumed, so it is not inert, but it is
  ambiguous.
- **Renamed docs on a move.** The github adapter writes `<into><repo-name>.md`. A brain that
  renamed files while moving them will get a second file beside the renamed one on the next sync.
