---
description: Check sync freshness against upstream reality — flag behind, stale, never-run, or broken syncs.
---

Run the health check in `pipeline/sync-health.md`.

Produce a status table: each enabled source (its `label`, else its `id`) · its derived output's `last-synced` · expected
cadence · **upstream** · status.

The **upstream** column is the point of this command. For each source type with an enabled
entry, run its gate script once, with no ids: `bash .brainforge/gate-<type>.sh` (`repos` →
`github`, `websites` → `website`, any other key is its own name) — the same gate `/sync` runs.
Read each line's `status` and `delta` per `pipeline/sync-health.md` step 1: `changed` → **N
changed**, N = the length of `delta`; `unchanged` → **0 changed**; `never` → **never synced**;
`blocked` → **blocked (<reason>)**; `not-checked` → **not checked (<reason>)**. The script
missing, exiting non-zero, or printing no line for an entry → **not checked (gate failed)**.
There is no prose fallback: never rebuild the adapter's §1 by hand, never guess the number, and
never leave the column blank.

The **expected** column shows the **resolved** cadence — the source's own `cadence` in
`sources.json`, or the `weekly` default when it has none (`pipeline/README.md` § Defaults). Mark
a defaulted value so the owner can see it was not configured, e.g. `weekly (default)`.

**Status follows reality, not the calendar.** Any in-scope upstream change is ⚠️ behind, with the
count. Zero upstream changes is ✅ current *even if the cadence says otherwise* — nothing changed,
so there is nothing to sync. Cadence decides only where the gate could not run, and say so when
it does. `blocked` is ⚠️ blocked whatever the cadence: ask the owner. Flag anything never-synced
or with a `TODO` source.

Read-only — no PR. Make staleness loud, not silent, and make it true.
