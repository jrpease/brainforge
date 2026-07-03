---
description: Sync derived context from sources (incremental by default). Args scope the work.
---

Sync upstream sources into `context/derived/`, following the adapters in `pipeline/adapters/`.

**Arguments:** `$ARGUMENTS`

Interpret the argument and scope accordingly:
- (empty) → **incremental sync of ALL enabled sources** (run every cheap gate, extract only
  deltas). Cheap when little changed.
- `<source-type>` (a top-level array in `sources.json`, e.g. `figma` | `repos` | `websites`) →
  sync only that source type.
- `<source-type> <id-or-key>` → sync only that **one unit** (e.g. `figma <fileKey>`, `repo <name>`).
- `--full` → ignore `.sync-state.json` and force full re-extraction (rare: first run, or
  suspected drift). Confirm with the user before doing this — it's the expensive path.

Always:
1. Run the **cheap change-detection gate first** (see the relevant `pipeline/adapters/<source>.md`).
   If nothing changed, say so and stop — do not extract.
2. Use **REST APIs, not MCPs**, for extraction (except where an adapter documents an exception).
3. Stamp `last-synced` / `source` / `generated-by` frontmatter and update `.sync-state.json`.
4. **Open a PR — never push derived changes to main directly.** Summarize what changed.
