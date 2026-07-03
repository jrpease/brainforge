# Playbook: sync Monday boards  (built-in adapter)

Covers: roadmap/initiatives + task-status across the team's Monday boards — "what the team is
working toward, and the live status of work." Auth: `MONDAY_API_TOKEN` from `.env` (add it to
`.env.example`). Monday has **no REST API** — it's GraphQL-only (single endpoint
`https://api.monday.com/v2`, token in the `Authorization` header). This GraphQL-over-HTTP endpoint
IS the cheap direct call golden rule #2 means — the heavy, token-hungry MCP is still avoided.

## 0. Inputs
- `sources.json` → `monday[]` (explicit board allowlist — filter `enabled: true`, or the one
  `boardId` passed as arg). Locator field: `boardId`.
- `.sync-state.json` → `monday[<boardId>]` (last fingerprint).

## 1. Cheap change gate (always)  — golden rule #1
One GraphQL call covering every allowlisted board:
```
POST https://api.monday.com/v2      header: Authorization: $MONDAY_API_TOKEN
query ($ids:[ID!]) { boards (ids:$ids) { id name updated_at items_count } }
```
- Fingerprint per board = `(updated_at, items_count)`. All match stored → **stop. Nothing changed.**
  (zero heavy calls)
- Else → the boards whose fingerprint moved are the delta scope.
- **Verify, don't assume:** the fingerprint `(updated_at, items_count)` catches added/removed items,
  but the first live run did not exercise an edit-then-resync — so whether `updated_at` bumps on a
  pure in-place *column* edit is unconfirmed. If it doesn't, such an edit slips past the gate. When
  correctness matters, treat `activity_logs` (see §2) as the authoritative delta detector, or switch
  the fingerprint to its latest event timestamp. Pin this against the real board.

## 2. Extract only the delta
- **Which items changed (deterministic):** `activity_logs(from: <lastSync>)` returns the events
  (item created/updated/column changed) since the last sync. The changed item's id is **not** the
  log's own `id` — it lives in the `data` field (a JSON string with `pulse_id`/`board_id`/
  `column_id`); parse `pulse_id` for the item id:
  ```
  query ($ids:[ID!],$from:ISO8601DateTime) {
    boards (ids:$ids) { activity_logs (from:$from) { id event created_at data } } }
  ```
  If `activity_logs` is empty or expired (Monday caps log retention on lower plans), fall back to
  paging items and comparing each item's `updated_at` to the stored fingerprint time.
  Monday has no cheap "changed-items-only" page fetch, so the delta pattern is: gate cheaply (§1),
  then full-page only the **boards** whose fingerprint moved — the `pulse_id`s above drive targeted
  diffing/refresh, not a server-side item filter.
- **Discover columns first (deterministic + safety):** before building tables, list each board's
  columns and their `type`. Use it to (a) **enforce the PII rule programmatically** — exclude any
  `email`/`phone`-typed column; (b) skip uninformative columns (e.g. the auto `Subitems` column,
  empty on every row). Watch `mirror`/`board_relation`/`doc` columns: `column_values.text` is often
  empty for these — read the typed field (e.g. `... on MirrorValue { display_value }`) if you need
  the value.
- **Fetch the changed items (deterministic):** Monday paginates in **two** calls — the first page
  from `items_page(limit:100)`, every page after it from `next_items_page(limit:100, cursor:<prev>)`,
  **not** by re-calling `items_page`:
  ```
  # page 1
  query ($ids:[ID!]) { boards (ids:$ids) {
    id name groups { id title }
    items_page (limit: 100) { cursor items {
      id name updated_at group { id } column_values { id text column { title type } } } } } }
  # pages 2..N — repeat with the previous page's cursor until cursor is null
  query ($cursor:String!) { next_items_page (limit: 100, cursor:$cursor) {
    cursor items { id name group { id } column_values { id text column { title type } } } } }
  ```
  Follow the `cursor` chain until it is null (a ~1000-item board is ~11 pages).
  - **Counts & enumerations come from `items_count` / the API's own count fields — never eyeballed or
    narrated** (golden rule #3). A fabricated count becomes "truth" downstream.
- **No narrative pass by default** — roadmap/task boards are structured (columns); render them
  faithfully. Add at most a one-line factual board summary if genuinely useful.
- **Transport (golden rule #2):** Monday GraphQL over HTTP with the token — the cheap direct
  endpoint. Not the MCP.
- **Emit to:** `context/derived/monday/<board>.md` — table-first, items grouped by the board's Monday
  groups (one table per group: item · owner · status · timeline/due · the board's key columns). A
  roadmap board becomes `roadmap.md`. Also refresh `context/derived/monday/_index.md` (cross-board
  overview: board · item count · last-synced).

## 3. Finish  — golden rule #5
- Stamp `source` / `last-synced` / `generated-by` on every file touched.
- Update `.sync-state.json` → `monday[<boardId>]` with the new `(updated_at, items_count)` fingerprint.
- **Branch + PR — never push to main directly (golden rule #4).**

## Never
- **Never crawl the whole workspace** — sync only the board IDs allowlisted in `sources.json`. This is
  what keeps HR / private / CRM boards out of the brain.
- No person-column PII beyond display-name owners — exclude any `email`/`phone`-typed column (the
  §2 column-discovery pass is how you catch them); `people`-type columns (display names) are fine.
- No raw attachments committed — store asset URLs only.

## Reminder: the source owns its own truth
This produces a *read-only snapshot for cross-team context*. Work happens in Monday; it flows here on
the next sync — never the reverse.
