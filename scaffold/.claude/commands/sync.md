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
3. Stamp `last-synced` / `source` / `generated-by` frontmatter and update `.sync-state.json`:
   the per-source fingerprint **and** `lastFullSync` (set it to today, `YYYY-MM-DD`, on every
   successful completion). The session-start tripwire in `.claude/settings.json` stays armed until
   `lastFullSync` stops being `null`, so skipping it means nudging the owner forever after a sync
   that actually worked.

### Regenerate the manifest (always, before the PR)

First keep a copy of the previous manifest — the generator overwrites
`.brainforge/brain-manifest.json` in place, and golden rule 6's growth check below needs the old
numbers:

```bash
git show HEAD:.brainforge/brain-manifest.json > /tmp/brain-manifest.prev.json 2>/dev/null || true
```

On a brain's first sync there is no committed manifest, so that file will be missing or empty.
That is expected: it means no growth baseline exists yet, not that the check failed.

Then run `bash .brainforge/gen-manifest.sh`. The manifest is a core brain artifact (DESIGN.md §9)
and regenerates on every sync so consumers never read a stale map. Include
`.brainforge/brain-manifest.json` in this sync's PR.

**If the generator reports unclassified domains** (or the manifest's `unclassified` list is
non-empty): propose a classification for each from the kinds catalog (`setup/README.md` §1a) —
one line per domain, e.g. `context/derived/monday -> kinds: [project-tracking]` — and ask the
human to confirm or correct. On confirmation, write the `kinds:` line into that domain's
`_index.md` frontmatter, re-run the generator, and include those edits in the same PR. Never
classify silently; never leave a new domain out of the map.

While the manifest is fresh, apply golden rule 6. For each emitted doc **that the manifest
measures**, take its `tokens` from `.brainforge/brain-manifest.json` and resolve its envelope, most
specific first:

1. an `acceptedSize` entry for that doc on the source's `sources.json` entry,
2. the adapter's declared `Size envelope:` in its §2,
3. the shipped default — any derived doc ≤ 8k (`pipeline/README.md` § Defaults).

The generator excludes `_index.md` from every domain's `files[]`, so an `_index.md` has no `tokens`
figure to read. Rule 6 cannot be applied to one — do not guess a count for it.

Flag a doc that is over the resolved value, **or** that grew ≥3× since the copy of the previous
manifest captured above (`/tmp/brain-manifest.prev.json`) — the growth check applies even to an
accepted doc. A doc absent from that captured copy, or a first sync where no copy exists, is
checked against the envelope only. Each flagged doc gets a line in the PR body:
`⚠ rule-6: <path> is <N> tokens (envelope <M> / was <P>) — consider aggregating.`

If the owner decides a breach is correct, add an `acceptedSize` entry (doc, tokens, since, why) to
that source in `sources.json` in the same PR. That silences the line until the doc exceeds the
accepted number or triples again. Never silence it by removing the envelope.

4. **Open a PR — never push derived changes to main directly.** Summarize what changed.
