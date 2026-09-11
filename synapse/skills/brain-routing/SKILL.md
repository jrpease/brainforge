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
3. Apply the band gate. It has **two levels**, because an `_index.md` is a separate and much
   smaller cost than the domain it indexes — the manifest reports it as `indexTokens`,
   distinct from the domain's total `tokens`:
   - **Index peek — permitted at any band**, on any domain that is plausibly relevant,
     including one whose kinds did not match and one that declares no kinds at all. A peek
     costs `indexTokens`, not `tokens`. This is the only way to find a file whose topic its
     domain's kinds do not cover: kinds are declared per *domain*, files are per *file*, and
     the `_index.md` doc table is the one place that gap is visible. Never skip a plausible
     domain for being expensive — expensive gates the *read*, not the *peek*.
   - **Full read** — **cheap**: on a weak match (any collected kind, or clear topical
     adjacency). **normal**: on a direct intent match only. **expensive**: on a direct match
     only, and NEVER the whole domain — open only the specific files the peek showed you need.
     A peek shows you need a file only when its index row names the task's subject outright
     (a renewal question, a `vendor renewal dates` row). A row that merely *might* hold
     something useful (a `milestone tracker` row, for a launch email) is not a match: do not
     open that file, not even its first lines, to find out. No such row → the peek ends there.
4. Three map signals mean "peek this index even though the intent match did not select it."
   Treat the domain as plausibly relevant whenever the task is near its subject, and say so in
   the announce line.
   - `⚠ unroutable kind ...` — the domain declares a kind no intent points at, so that content
     cannot be reached by intent at all. A defect, and the owner is being told.
   - `· single-intent` on a domain line — exactly one intent reaches that whole domain. Not a
     defect: most kinds are single-intent by design and every adapter emits one. It matters
     because a domain that is *also* `expensive` needs a direct match for a full read, so if
     the task is not phrased as that one intent, the index peek is the only way in. This is the
     shape that hides a large domain holding the only accurate doc on its subject.
   - `- unindexed: <path>` — a directory holding content with no `_index.md`. Routing cannot
     reach it at all and the map cannot describe it. If it is plausibly relevant, read the
     files directly and say that you did.
5. Read the chosen domains' `_index.md` files, then the specific content files. Prefer
   targeted reads; the disclosure ladder is map → index → files.

## Announce (one line, every grounded response)

`🧠 loaded: <domain titles> · skipped: <notable skipped domains or none>`

This line is the under-fetch detector and the telemetry that improves routing for everyone —
never omit it when you loaded (or deliberately skipped) brain content.

## Ground rules

- Canon (`context/canon/`) is authored truth; derived (`context/derived/`) is regenerated from
  an upstream source — cite which file informed the result, and flag stale `last-synced` rather
  than asserting currency. Derived is deliberately *not* a copy of its source, so treat it as a
  summary that may omit detail the source holds, never as the source itself.
- If canon and derived contradict, surface the conflict (that is drift); never silently pick one.
- If the map warned that it **predates the current content**, or that staleness **cannot be
  checked** (a pre-schema-3 map), trust domain `_index.md` files over the map's token counts and
  band assignments. Both warnings are about the map's numbers, never about the content itself.
- If the prompt has nothing to do with the brain: do nothing, say nothing.
- Write outputs to the user's workspace, never into the brain (it is read-only reference;
  suggest changes via its CONTRIBUTING.md).
