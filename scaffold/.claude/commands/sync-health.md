---
description: Check sync freshness — flag stale, never-run, or broken syncs.
---

Run the health check in `pipeline/sync-health.md`.

Produce a status table: each enabled source · its derived output's `last-synced` · expected
cadence · status (✅ current / ⚠️ stale / ❌ never). The expected column shows the **resolved**
cadence — the source's own `cadence` in `sources.json`, or the `weekly` default when it has none
(`pipeline/README.md` § Defaults). Mark a defaulted value so the owner can see it was not
configured, e.g. `weekly (default)`. Flag anything stale, never-synced, or with a `TODO` source.
Read-only — no PR. Make staleness loud, not silent.
