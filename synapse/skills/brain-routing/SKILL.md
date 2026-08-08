---
name: brain-routing
description: Use when a task should be grounded in the org's brain — building or prototyping UI, writing user-facing copy, naming a feature or product, making design or art-direction decisions, answering metrics/analytics or roadmap/status questions, citing engineering architecture, or whenever brand voice, design tokens, product principles, or any org fact is needed. Also use when the user names the brain or a subscribed brain's map appears in context.
---

# brain-routing — open the right slice of the brain

A brain's session map (from the synapse hook) lists its domains as:
`- <title> (<path>) [<kinds>] — <band>`. Your job: open the relevant slice, announce what you
did, and never appear grounded when you are not.

## Locate the brain

1. Subscribed brains live at `$SYNAPSE_HOME` (default `~/.synapse`)`/<name>/` — the map shows
   the exact path — always use the map's path, never reconstruct it from the brain name (collision-suffixed directories exist).
2. If the current working directory is itself a brain (it has `.brainforge/brain-manifest.json`),
   use that manifest directly.
3. No map, no manifest, no brain directory → say plainly that you are proceeding ungrounded.
   Never fabricate brain content. These two sources are the only ones that count — do not go
   searching the rest of the filesystem for some unrelated directory that happens to have a
   `.brainforge/brain-manifest.json` (e.g. a stray clone on disk); a brain found that way is not
   what this session subscribes to or runs from, and grounding in it would misrepresent what
   actually informed the answer. Report ungrounded instead.

## Route

1. Read `${CLAUDE_PLUGIN_ROOT}/routing/intents.json`. Match the task to one or more intents;
   collect their kinds.
2. From the brain's manifest, select domains whose `kinds` intersect the collected kinds —
   skipping nothing silently: unmatched but plausibly relevant domains may load per band.
3. Apply the band gate:
   - **cheap** — load on a weak match (any collected kind, or clear topical adjacency).
   - **normal** — load on a direct intent match only.
   - **expensive** — direct match only — not even an index peek on an unmatched-but-plausible
     domain, that's for cheap/normal only — and NEVER the whole domain: read the domain's
     `_index.md`, then open only the specific files the task needs.
4. Read the chosen domains' `_index.md` files, then the specific content files. Prefer
   targeted reads; the disclosure ladder is map → index → files.

## Announce (one line, every grounded response)

`🧠 loaded: <domain titles> · skipped: <notable skipped domains or none>`

This line is the under-fetch detector and the telemetry that improves routing for everyone —
never omit it when you loaded (or deliberately skipped) brain content.

## Ground rules

- Canon (`context/canon/`) is authored truth; derived (`context/derived/`) is a synced mirror —
  cite which file informed the result, and flag stale `last-synced` rather than asserting
  currency.
- If canon and derived contradict, surface the conflict (that is drift); never silently pick one.
- If the map warned the manifest predates the latest change, trust `_index.md` files over the
  map's numbers.
- If the prompt has nothing to do with the brain: do nothing, say nothing.
- Write outputs to the user's workspace, never into the brain (it is read-only reference;
  suggest changes via its CONTRIBUTING.md).
