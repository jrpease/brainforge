# Monday adapter — proof summary

**Proven live:** 2026-07-02 · **Source system:** a production work-management workspace

## What was proven

- A live sync ran against a real workspace over a personal API token — the clean,
  unattended-steady-state path, with no dead-token caveat.
- Deterministic extraction of 4 allowlisted boards via two-step pagination (`items_page` for the
  first page, `next_items_page` with a cursor thereafter): item counts of 13, 208, 30, and 1053
  respectively, the largest fully enumerated across roughly 11 pages with no truncation.
- Derived files with provenance were written one per board, plus an index — additive to the brain's
  existing sources, with nothing else touched.
- Golden rule #1 proven live: a second cheap-gate run matched every `(updated_at, items_count)`
  fingerprint against stored state → zero heavy calls.
- Data-faithfulness review independently re-queried the live API: all four counts matched exactly,
  row-for-row on the smallest board and a 60-group reconciliation summing correctly on the largest —
  no fabricated counts.

## What the live run hardened

- Two-step pagination is now documented explicitly in the adapter doc (`items_page` for page one,
  `next_items_page` with a cursor for every page after — not re-calling `items_page`).
- A column-discovery pass was added: enumerate each board's columns and their type first, to enforce
  PII exclusion (email/phone columns) programmatically and skip uninformative columns.
- A fingerprint caveat was noted: whether `updated_at` bumps on a pure in-place column edit is
  unconfirmed by this run; `activity_logs` is the authoritative delta source when correctness matters.
