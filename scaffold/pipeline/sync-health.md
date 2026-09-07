# Playbook: sync health

Makes staleness **visible** so nobody trusts silently-broken truth.

## Checks
1. For each `enabled` source in `sources.json`, read the `last-synced` of its derived output.
2. Flag any source whose `last-synced` is older than its resolved cadence. Resolve it as: the
   entry's `cadence` in `sources.json`, else the `weekly` default (`../pipeline/README.md`
   § Defaults). `manual` is never stale. "Never" on an enabled source = not yet wired → flag.
   Never invent a cadence — resolve it, and say which value you used.
3. Flag sources present in `sources.json` but missing a `.sync-state.json` fingerprint
   (sync never completed).
4. Flag derived files whose `source` still says `TODO`.

## Output
A short status table: source · last-synced · expected · status (✅ current / ⚠️ stale / ❌ never).
Read-only — no PR. Run it before relying on the repo for anything important, and as part of the
scheduled agent so a failed run is loud, not silent.
