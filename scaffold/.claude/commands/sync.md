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

### Regenerate the manifest (always, before the PR)

Run `bash .brainforge/gen-manifest.sh`. The manifest is a core brain artifact (DESIGN.md §9)
and regenerates on every sync so consumers never read a stale map. Include
`.brainforge/brain-manifest.json` in this sync's PR.

**If the generator reports unclassified domains** (or the manifest's `unclassified` list is
non-empty): propose a classification for each from the kinds catalog (`setup/README.md` §1a) —
one line per domain, e.g. `context/derived/monday -> kinds: [project-tracking]` — and ask the
human to confirm or correct. On confirmation, write the `kinds:` line into that domain's
`_index.md` frontmatter, re-run the generator, and include those edits in the same PR. Never
classify silently; never leave a new domain out of the map.

While the manifest is fresh, apply golden rule 6: compare each emitted doc's `tokens` (from
`.brainforge/brain-manifest.json`) against the adapter's declared size envelope, and against
the previous manifest if one existed. Any doc over-envelope or grown ≥3× gets a line in the
PR body: `⚠ rule-6: <path> is <N> tokens (envelope <M> / was <P>) — consider aggregating.`

4. **Open a PR — never push derived changes to main directly.** Summarize what changed.
