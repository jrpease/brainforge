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
- `--full` → run the gates as usual, then extract everything for every `unchanged`, `changed`
  and `never` entry, ignoring `delta` (full re-extraction; rare: first run, or suspected drift).
  `blocked` and `not-checked` entries still skip. Confirm with the user before doing this — it's
  the expensive path.

Always:
0. **Run `bash .brainforge/sync-contract.sh` before anything else.** Exit 1 → relay its output and
   **stop; sync nothing**. It fails when an enabled source entry has no `into:`, or one outside
   `context/derived/` or missing its trailing `/`; when an adapter playbook hardcodes a destination
   folder, writes a `kinds:` value, or never names `into:`; and when `python3` is missing, since
   then nothing was checked. Never work around it by syncing to the
   adapter's conventional folder: that is the fallback that writes a brain's moved docs back over
   the move (`pipeline/README.md` § Where a sync writes).
1. Run the **cheap change-detection gate first, as its script**:
   `bash .brainforge/gate-<type>.sh [<id>…]`. `<type>` is the adapter's name: `repos` → `github`,
   `websites` → `website`, any other key is its own name. For one unit, pass that entry's `id`
   (resolve a `fileKey`, repo name or board to its entry first). For a whole type or a bare
   `/sync`, pass no ids, so each type's gate runs once (Monday's one call covers every board). The
   gate prints one JSON line per entry (`.brainforge/README.md` § Gate scripts). Route on `status`:
   - `unchanged` → nothing to extract for that entry. All unchanged → say so and stop.
   - `changed` → extract that entry's `delta`, per the adapter's §2. (figma: `delta` is always
     empty; the file changed, and §2's per-resource checks decide what to re-extract.)
   - `never` → extract regardless (no stored slot, or a figma entry whose `<into>` is still empty).
   - `blocked` → do not sync that source. Relay `reason` and ask the owner.
   - `not-checked` → skip that source and report `not-checked (<reason>)`.
   - Built-in types: `figma`, `ga`, `github`, `monday`, `website` (each ships a `gate-<type>.sh`). For a built-in, the script
     missing, exiting non-zero, or printing no line for an entry → that source is
     `not-checked (gate failed)`, never unchanged. **There is no prose fallback:** do not rebuild
     the adapter's §1 call by hand.
   - Any other type is a custom adapter (added with `/add-adapter`, e.g. `notion`) and ships no gate
     script: run its §1 as written, because that is its only gate.

   `--full` still runs the gate, then extracts everything for each `unchanged`, `changed` and
   `never` entry, ignoring `delta`; `blocked` and `not-checked` still skip the source.
2. Use **REST APIs, not MCPs**, for extraction (except where an adapter documents an exception).
3. Stamp `last-synced` / `source` / `generated-by` frontmatter and update `.sync-state.json`:
   the per-source fingerprint, that source's `"synced": true`, **and** `lastFullSync` (set it to
   today, `YYYY-MM-DD`, on every successful completion). The fingerprint is the gate's
   `fingerprint`, stored verbatim; when it is `null` (a `never` entry), the adapter's §3 says how
   to build it. The session-start tripwire in `.brainforge/session-start.sh` stays armed while
   any source's slot says `"synced": false`, or while `lastFullSync` is `null`, so skipping either
   means nudging the owner forever after a sync that actually worked.

### Regenerate the manifest (always, before the PR)

First keep a copy of the previous manifest — the generator overwrites
`.brainforge/brain-manifest.json` in place, and golden rule 6's growth check below needs the old
numbers:

```bash
PREV="$(mktemp -t brain-manifest.prev)"
git show HEAD:.brainforge/brain-manifest.json > "$PREV" 2>/dev/null || true
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

While the manifest is fresh, apply golden rule 6 with the script, never by hand:

```bash
bash .brainforge/envelope-check.sh "$PREV" .brainforge/brain-manifest.json sources.json [<source-id>…]
```

Pass the ids of the sources this run synced, or none after a bare `/sync` (it then checks every
enabled source). It checks every doc and `_index.md` in each source's `into:` domain, and the
domain total. A doc's envelope is its `acceptedSize`, else the adapter's `0a. Size envelope` row,
else 8,000. It also flags 3× growth since `$PREV`. Paste every `⚠ rule-6:` line it prints into
the PR body verbatim. No output means nothing breached. Exit 1 means nothing was checked: relay
its message and say in the PR body that golden rule 6 was not checked.

If the owner decides a breach is correct, add an `acceptedSize` entry (doc, tokens, since, why) to
that source in `sources.json` in the same PR. That silences the line until the doc exceeds the
accepted number or triples again. Never silence it by removing the envelope.

4. **Open a PR — never push derived changes to main directly.** Summarize what changed, naming
   each source by its `label` (else its `id`).
