# Pipeline — how sources become `derived/` context

These playbooks are instructions the maintainer's LLM follows to sync. They are **not**
consumed by readers. The golden rules, applied by every playbook:

## 1. Work scales with the delta, not the corpus
Always run the **cheap change-detection gate first**, then do expensive extraction **only on
what changed**. A sync where nothing changed should finish in seconds. Never re-extract a whole
Figma file because one frame moved.

| Source | Cheap gate (always) | Heavy work (delta only) |
|---|---|---|
| Repo | `git diff <lastSha>..HEAD --name-only` | re-summarize affected areas |
| Figma | file `version`/`lastModified` via REST → then `depth=1` node diff | export/extract changed nodes |
| Website | sitemap `<lastmod>` + HTTP `ETag`/`If-Modified-Since` (304 = free) | refetch changed URLs |
| Shopify | max product `updated_at` + resource counts via Admin REST | re-extract changed products/collections |
| GA (metrics) | `sessions` by `date` over a trailing window (dates + per-day count) | re-pull only new/restated days (append-merge) |

## 2. REST API, not MCP
The Figma/browser **MCPs are heavy and token-hungry** — built for interactive design, not bulk
sync. Sync uses cheap **REST endpoints** (Figma REST API; plain `fetch` + sitemap for sites).
Reserve the MCP for when a human is actually designing, or for the rare node that needs rich
semantic understanding — scoped to that one node. (Documented exceptions, where REST genuinely
cannot reach the data, are called out in the adapter that needs them.)

## 3. Deterministic extraction over LLM summarization
Prefer tooling that produces the same output every run (e.g. Style Dictionary for tokens).
Use an LLM pass **only** for genuinely narrative output (e.g. "describe this repo's checkout
flow"), and gate it hardest — a wrong word becomes "truth."

## 4. Every sync lands via PR, never a direct write
A sync **proposes** changes on a branch and opens a PR. The maintainer eyeballs the diff and
merges. Garbage never silently propagates to everyone's LLM. This is the human trust gate.

## 5. Always update provenance + state
- Write `source` / `last-synced` / `generated-by` frontmatter on every derived file.
- Update `.sync-state.json` with the new fingerprint at the end of a successful sync.

## 6. Extraction produces reference, not mirrors
A derived doc is what an LLM reasons *from* — inventories, definitions, aggregates — never a
replica of the source's records. (Measured failure this rule exists to prevent: one synced
task-board doc grew to ~30k tokens, 48% of an entire brain.) Every emitted doc has a
**size envelope** — the adapter's, declared in its own `0a. Size envelope` section (see
`ADAPTER-TEMPLATE.md`), otherwise the shipped default (see § Defaults below). Golden rule 6: A sync that lands a doc over its envelope — or grows one past 3×
its previous size — MUST say so in the PR body: what grew, by how much, and whether the extraction
should aggregate harder. The human decides at the gate; the rule makes the growth loud, not
forbidden. A breach the owner accepts is recorded as an `acceptedSize` entry, not ignored.

## Defaults — so a rule always has something to compare against

A rule whose data nobody remembered to write down cannot fire. These defaults always apply, so
every check has a value even when no adapter or source declares one. Declaring a value is a
refinement, never a precondition.

**Sync cadence** (staleness expectation, not a schedule — nothing runs syncs on a timer):

| Value | Means | Stale after |
|---|---|---|
| `daily` | expected every day | 1 day |
| `weekly` | expected weekly | 7 days |
| `monthly` | expected monthly | 31 days |
| `manual` | run by hand | never stale |

A source entry sets `"cadence"` in `sources.json`. **A source with no `cadence` is treated as
`weekly`.** `/sync-health` resolves the value, compares it to the derived output's `last-synced`,
and reports ✅ current / ⚠️ stale / ❌ never.

**Size envelope** (expected tokens per emitted doc, golden rule 6). Most specific wins:

| Precedence | Where | Owner |
|---|---|---|
| 1 | `acceptedSize[<doc>]` on the `sources.json` entry | the brain |
| 2 | the adapter's `0a. Size envelope` table | the adapter |
| 3 | the default below | shipped |

**Default: any derived doc ≤ 8k tokens.**

`/sync` checks `_index.md` rows from the manifest's `indexTokens`, the figure
`.brainforge/gen-manifest.sh` records for each domain's `_index.md`.

`acceptedSize` records a knowingly-oversized doc so the warning stops without being ignored. It is
an array on the source entry, with `doc` relative to that entry's `into:` folder:

    "acceptedSize": [
      { "doc": "milestones.md", "tokens": 32000, "since": "2026-08-12",
        "why": "item-level detail is what cross-team reads use this board for" }
    ]

It lives on the source entry, in `sources.json`, because it is **brain-specific**. An adapter
playbook is under the `pipeline/**` bump glob and would be overwritten on the next `/upgrade`.

The 3× growth check is independent of acceptance: an accepted doc that triples again still gets
flagged. A doc with no previous manifest entry is compared against its envelope only — there is no
growth baseline, and none is invented.

## Source-declared scope — the boundary travels with the source

Registry config in `sources.json` says what a brain *wants* from a source. A source repo can
also declare what it will **never** hand over, in a `.brainforge-source.yml` at its own root.
The two compose in one direction only: the in-repo declaration narrows scope, never widens it.

This exists because the alternative does not survive time. A prose note in a registry entry the
source's owners cannot edit protects nothing the day someone re-scopes that source for perfectly
good reasons and never reads the paragraph. The people who own named-customer material are the
people who should be able to see and change the rule that protects it, in their own review,
next to the content it covers.

`adapters/github.md` §0b defines the file and its force order. An adapter whose source can carry
a file honours it identically; one whose source cannot (Figma, Monday, GA) falls back to
registry scope alone.

## Adapters & playbooks
Built-in **adapters** (one per source type) live in `adapters/`; cross-source orchestration and
analysis live here. Every adapter fills the same skeleton — see `ADAPTER-TEMPLATE.md`.

- `adapters/figma.md` — design tokens, component inventory, frames/dielines
- `adapters/github.md` — code repo summaries
- `adapters/website.md` — live-site page inventory
- `adapters/monday.md` — roadmap/initiatives + task-status across Monday boards (GraphQL)
- `adapters/ga.md` — GA4 traffic / acquisition / top-pages / ecommerce (metrics, time-series)
- `examples/shopify.md` — **worked extension example**, built by filling `ADAPTER-TEMPLATE.md` (run `/add-adapter`)
- `ADAPTER-TEMPLATE.md` — the canonical gate → extract → emit → provenance → command skeleton
- `sync-all.md` — orchestration + scheduled-agent recipe
- `drift-report.md` — find where canon disagrees with derived reality
- `sync-health.md` — detect stale/failed syncs
