---
description: Check sync freshness — flag stale, never-run, or broken syncs.
---

Run the health check in `pipeline/sync-health.md`.

Produce a status table: each enabled source · its derived output's `last-synced` · expected
cadence · status (✅ current / ⚠️ stale / ❌ never). Flag anything stale, never-synced, or with
a `TODO` source. Read-only — no PR. Make staleness loud, not silent.
