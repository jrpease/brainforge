# Playbook: sync everything (orchestration)

Runs every enabled source's cheap gate, extracts only deltas, and opens **one** PR with all
changes. Because each source short-circuits when unchanged, "sync all" is cheap by default.

## Steps
0. Run `bash .brainforge/sync-contract.sh`. Exit 1 → report its output and exit. No gates, no PR.
1. Load `sources.json`. For each source type with an `enabled: true` entry, run its **cheap
   gate script once, with no ids**: `bash .brainforge/gate-<type>.sh` (`repos` → `github`,
   `websites` → `website`, any other key is its own name). It prints one JSON line per enabled
   entry; route each as `/sync` step 1 says. Built-in types: `figma`, `ga`, `github`, `monday`, `website`. For a built-in there is no prose fallback: a
   missing script, a non-zero exit or an entry with no line is `not-checked (gate failed)`. Any
   other type is a custom adapter with no gate script: run its `adapters/<source-type>.md` §1 as
   written.
2. Collect the sources whose `status` is `changed` or `never`. Report each `blocked` source with
   its `reason` (ask the owner) and each `not-checked` one with its reason. Neither syncs.
3. If nothing changed → report "all current" and exit. No PR.
4. For changed sources only, run extraction (per adapter).
5. Stamp provenance, update `.sync-state.json`: each changed source's fingerprint (the gate's
   `fingerprint`, verbatim) and `"synced": true` in its slot, per its adapter, then
   `lastFullSync` to today (`YYYY-MM-DD`).
   The session-start sync-health tripwire stays lit while any source's `synced` is `false` or
   `lastFullSync` is `null`.
6. Open a single PR titled `sync: <date> — <which sources changed>`, naming each by its `label`
   (else its `id`). Maintainer reviews + merges.

## Scheduled-agent recipe
Run this on a cadence (nightly or weekly) as a scheduled Claude agent:
- It will mostly find nothing changed and exit cheaply.
- When something changed, it opens a PR — it never merges to main unattended.
- Pair with `/sync-health` so a *failed or skipped* sched run is visible, not silent.

> Event-driven sync replaces polling later: a Figma `FILE_UPDATE` webhook or repo CI calls the
> relevant per-source sync with the exact changed scope. Until then, scheduled + cheap-gate is
> the right balance.
