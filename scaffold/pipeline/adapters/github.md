# Playbook: sync a code repo  (built-in adapter)

The cheapest source — change detection is just local git. `GITHUB_TOKEN` from `.env` for
private-repo read access (read-only contents scope is enough).

## 0. Inputs
- `sources.json` → `repos[]`
- `.sync-state.json` → `repos[<id>].lastSha`

## 0a. Size envelope  — golden rule #6

| Emitted doc | Envelope |
|---|---|
| `repos/<repo-name>.md` | ≤ 2,500 each |
| `repos/_index.md` | ≤ 1,500 |
| **domain total** | **≤ 8,000** |

**Emit reference, not a file listing.** Directory *names* and counts, the stack table, the route or
page registry, key components, and what changed since the last sha. Never per-file inventories, never
source excerpts, never a dependency dump — a package manifest can carry well over a hundred entries
of which perhaps thirty define the stack. A repo holds thousands of files and the summary must not
scale with them: if a repo doc is growing with the codebase rather than with its architecture, the
extraction is wrong, not the envelope.

## 1. Cheap change gate (always)
```
git -C <clone> fetch --quiet
git -C <clone> diff <lastSha>..origin/<branch> --name-only
```
- Empty diff → **stop.** Nothing changed.
- Else → you have the exact list of changed files. Map them to affected areas
  (routes/pages, components, config, docs).

## 2. Extract only the delta
- **Structured first (deterministic):** regenerate the route/page list and component list by
  reading the file tree — no LLM needed.
- **Narrative pass (LLM, gated):** only for changed areas that need description ("what does this
  flow do"), keep it short and factual. A wrong word here becomes "truth" — be conservative.
- Write to `context/derived/repos/<repo-name>.md`: stack, routes/pages, key components, notable
  changes since last sync.
## 3. Finish
- Stamp `source` / `last-synced` / `generated-by`.
- Update `.sync-state.json` → `repos[<id>].lastSha = origin/<branch> HEAD`.
- Set `.sync-state.json` → `lastFullSync` to today (`YYYY-MM-DD`). Disarms the session-start
  sync-health tripwire, which stays lit while that field is `null`.
- The emitted `_index.md` frontmatter MUST include `kinds: [repo-summaries]`.
- Branch + PR.

## Reminder: the repo owns its own truth
This produces a *summary for cross-team consumption*. Repo-specific implementation detail stays
in the repo. Do not pull canon down into the repo — the repo should *reference* canon
(see `templates/`).
