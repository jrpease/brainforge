---
description: Check sync freshness against upstream reality — flag behind, stale, never-run, or broken syncs.
---

Run the health check in `pipeline/sync-health.md`.

Produce a status table: each enabled source · its derived output's `last-synced` · expected
cadence · **upstream** · status.

The **upstream** column is the point of this command. For each source, run its adapter's cheap
change-detection gate — the same free gate `/sync` runs — and report **"N in-scope files changed
since `lastSha`"**, with the count filtered through that source's scope (registry `summarize`,
narrowed by any `.brainforge-source.yml`). A gate you cannot run is `not checked` **with its
reason** (`no clone` / `no credentials` / `offline`). Never guess the number, and never leave the
column blank.

The **expected** column shows the **resolved** cadence — the source's own `cadence` in
`sources.json`, or the `weekly` default when it has none (`pipeline/README.md` § Defaults). Mark
a defaulted value so the owner can see it was not configured, e.g. `weekly (default)`.

**Status follows reality, not the calendar.** Any in-scope upstream change is ⚠️ behind, with the
count. Zero upstream changes is ✅ current *even if the cadence says otherwise* — nothing changed,
so there is nothing to sync. Cadence decides only where the gate could not run, and say so when
it does. Flag anything never-synced or with a `TODO` source.

Read-only — no PR. Make staleness loud, not silent, and make it true.
