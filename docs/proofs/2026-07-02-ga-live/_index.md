---
source: GA4 property REDACTED (example property)
last-synced: 2026-07-01
generated-by: pipeline/adapters/ga.md (GA4 Data API runReport)
---

# GA4 Sync Index — property REDACTED (example property)

- **Property:** REDACTED (example property), reporting time zone America/Los_Angeles, currency USD.
- **Sync type:** cold-start backfill (first run, no prior `.sync-state.json` entry).
- **Config:** lookbackDays: 3 · backfillDays: 90 · rollupDays: 28.

## Date range covered per report
| Report | Window | Last synced through |
|---|---|---|
| traffic-overview | 2026-04-03 to 2026-07-01 (90-day backfill) | 2026-07-01 |
| ecommerce | 2026-04-03 to 2026-07-01 (90-day backfill) | 2026-07-01 |
| acquisition | 2026-06-04..2026-07-01 (trailing 28-day rollup) | 2026-07-01 |
| top-pages | 2026-06-04..2026-07-01 (trailing 28-day rollup, top 50) | 2026-07-01 |

## Notes
- `ecommerce.md` has 0 rows — the property has no ecommerce events in the 90-day window. This is
  expected (example property does not sell); the file is emitted with headers and a note, not a fabricated row.
- GA renamed `conversions` → `keyEvents`. This sync used `conversions` (the adapter's documented
  metric name); on this property `conversions` and `keyEvents` return identical values, so they are
  equivalent here.
- Auth: Application Default Credentials (own OAuth Desktop client, scope analytics.readonly) as
  the analyst account. Google's public GA4 demo properties are API-denied (429 RESOURCE_EXHAUSTED);
  this is a real, user-granted trafficked property.
