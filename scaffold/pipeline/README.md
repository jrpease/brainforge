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
