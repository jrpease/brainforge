# Playbook: sync everything (orchestration)

Runs every enabled source's cheap gate, extracts only deltas, and opens **one** PR with all
changes. Because each source short-circuits when unchanged, "sync all" is cheap by default.

## Steps
1. Load `sources.json`; for each `enabled: true` source, run its adapter's **cheap gate**
   (`adapters/<source-type>.md`).
2. Collect the set of sources that actually changed.
3. If nothing changed → report "all current" and exit. No PR.
4. For changed sources only, run extraction (per adapter).
5. Stamp provenance, update `.sync-state.json`.
6. Open a single PR titled `sync: <date> — <which sources changed>`. Maintainer reviews + merges.

## Scheduled-agent recipe
Run this on a cadence (nightly or weekly) as a scheduled Claude agent:
- It will mostly find nothing changed and exit cheaply.
- When something changed, it opens a PR — it never merges to main unattended.
- Pair with `/sync-health` so a *failed or skipped* sched run is visible, not silent.

> Event-driven sync replaces polling later: a Figma `FILE_UPDATE` webhook or repo CI calls the
> relevant per-source sync with the exact changed scope. Until then, scheduled + cheap-gate is
> the right balance.
