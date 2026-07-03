# Playbook: sync <SOURCE> — ADAPTER TEMPLATE

> Copy this file to `adapters/<source-type>.md` and fill every `<…>`. This is the **contract**:
> a new adapter is prose, but prose that fills a fixed skeleton. Don't reverse-engineer style
> from the built-ins — fill this. `/add-adapter` does exactly this. A worked example lives at
> `examples/shopify.md`.
>
> **Every adapter must honor the five golden rules in `../README.md`.** The skeleton below is
> structured so that filling it correctly *is* honoring them.

Covers: <what this source contributes to the brain — e.g. "design tokens + component inventory">.
Auth: `<CREDENTIAL_ENV_VAR>` from `.env` (add it to `.env.example`). <One line on the API used.>

## 0. Inputs
- Source entries from `sources.json` → `<source-type>[]` (filter `enabled: true`, or the one passed as arg)
- Last fingerprint from `.sync-state.json` → `<source-type>[<key>]`

## 1. Cheap change gate (always)  — golden rule #1
> The cheapest call that answers "did anything change?" — a version field, a `max(updated_at)`,
> an ETag, a git SHA. This is the whole game: an unchanged source must cost ~one cheap call.
```
<the cheap probe — e.g. GET …?fields=updated_at, or git diff <lastSha>..HEAD --name-only>
```
- Fingerprint == stored → **stop. Nothing changed.** (zero heavy calls)
- Else → compute the exact delta (which items/nodes/files changed) and extract only those.

> **Metrics / time-series sources** (e.g. Google Analytics) don't fit the stop-if-unchanged frame —
> their data changes every day by definition and recent days get **restated** as they finalize. There
> the cheap gate is a **date-bounded trailing fingerprint** (a tiny per-day metric over
> `[lastSyncedThrough − lookback, yesterday]`, e.g. `sessions` by `date`) and the delta is a **date
> window** (new + restated days), not a whole-source hash. Emit shapes split too: growing time series
> **append-merge** the window; bounded rollups **refresh-in-full**. See `adapters/ga.md` for the worked
> example.

## 2. Extract only the delta
- **Deterministic first (golden rule #3):** <the tooling/endpoint that yields identical output
  each run — prefer this for anything structured.>
  - **Counts & enumerations come from an authoritative count field — never eyeballed or narrated.**
    Read totals from the source's own count (e.g. a `…Count.count` field, a `total`, a paged
    `count`), not from how many items a narrative pass happened to list. A fabricated count becomes
    "truth" downstream and is nearly impossible to catch later.
- **Narrative pass (LLM, gated):** <only for genuinely narrative output; keep short + factual.
  A wrong word becomes "truth.">
- **Transport (golden rule #2):** use **REST**, not MCP. If REST genuinely cannot reach the data,
  document the exception here and scope the MCP use as tightly as possible.
- **Emit to:** `context/derived/<folder>/…` — <which files, in what shape (table-first).>

## 3. Finish  — golden rule #5
- Stamp `source` / `last-synced` / `generated-by` frontmatter on every file touched.
- Update `.sync-state.json` → `<source-type>[<key>]` with the new fingerprint.
- **Branch + PR — never push to main directly (golden rule #4).**

## Never
- <PII / secrets / out-of-scope resources this adapter must refuse to extract.>
- No raw binaries committed — store CDN/export URLs (or Git-LFS per `.gitattributes`).

## Reminder: the source owns its own truth
This produces a *read-only snapshot for cross-team context*. Edits happen in the source, then
flow here on the next sync — never the reverse.

---

### `sources.json` entry shape
```json
{
  "id": "<unique-id>",
  "label": "<human label>",
  "<locator-field>": "<file key / remote / url>",
  "extract": ["<what>", "<to>", "<pull>"],
  "into": "context/derived/<folder>/",
  "enabled": true,
  "$note": "<quirks, auth path, what to skip>"
}
```

### Generated command
`/sync <source-type>` already dispatches here via `sources.json`. No new command needed unless
the adapter has a bespoke mode — if so, add `.claude/commands/<name>.md` that points back here.

> **Replacing a built-in or flat playbook?** Then producing this file is only half the job — the
> dispatch must be *repointed* to it. Update the `.claude/commands/sync.md` reference and the
> `../README.md` Playbooks list to point at `adapters/<source-type>.md`, and supersede the old
> flat `sync-<source-type>.md`. A leftover flat playbook or an unrepointed dispatch means `/sync`
> still runs the stale path. (`/add-adapter` walks this.)
