# Playbook: sync health

Makes staleness **visible** so nobody trusts silently-broken truth.

## Checks
1. For each `enabled` source in `sources.json`, read the `last-synced` of its derived output.
2. Flag any source whose `last-synced` is older than its expected cadence (e.g. tokens weekly,
   site weekly). "Never" on an enabled source = not yet wired → flag.
3. Flag sources present in `sources.json` but missing a `.sync-state.json` fingerprint
   (sync never completed).
4. Flag derived files whose `source` still says `TODO`.

## Output
A short status table: source · last-synced · expected · status (✅ current / ⚠️ stale / ❌ never).
Read-only — no PR. Run it before relying on the repo for anything important, and as part of the
scheduled agent so a failed run is loud, not silent.
