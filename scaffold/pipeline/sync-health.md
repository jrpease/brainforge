# Playbook: sync health

Makes staleness **visible** so nobody trusts silently-broken truth.

Staleness is a fact about the upstream source, not about the calendar. Where the real answer is
free, take it. Fall back to cadence only where it is not, and always say which one you used.

## Checks

1. **Upstream reality — run this first.** For each `enabled` source, run its adapter's own cheap
   change-detection gate. It is the same gate `/sync` runs before every sync and it costs the
   same nothing: no LLM, no tokens. For a repo:

       git -C <clone> fetch --quiet
       git -C <clone> diff <lastSha>..origin/<branch> --name-only

   Filter the result through that source's scope — the registry's `summarize`, narrowed by any
   `.brainforge-source.yml` in the source repo. Read that declaration from the **fetched ref**
   (`git show origin/<branch>:.brainforge-source.yml`), never from the clone's working tree,
   which this command does not update either (`adapters/github.md` §0a-bis). Report the
   surviving count: **"N in-scope files changed upstream since `lastSha`."** Zero is an answer,
   not a failure.

   A gate that cannot run is reported as `not checked` **with its reason**. Never skip it
   silently and never guess the number:
   - `not checked (no clone)` — the entry has no `localClone` and this adapter needs one.
   - `not checked (no credentials)` — the gate needs auth that is not in `.env`.
   - `not checked (offline)` — the fetch or API call failed.

2. Read each source's derived output `last-synced` and resolve its expected cadence: the entry's
   `cadence` in `sources.json`, else the `weekly` default (`pipeline/README.md` § Defaults).
   `manual` is never stale. Mark a defaulted value, e.g. `weekly (default)`, so the owner can see
   it was never configured. Never invent a cadence — resolve it, and say which value you used.

3. Flag sources present in `sources.json` but missing a `.sync-state.json` fingerprint
   (sync never completed). "Never" on an enabled source = not yet wired → flag.

4. Flag derived files whose `source` still says `TODO`.

## The verdict — reality first, calendar second

| Upstream | Cadence | Verdict |
|---|---|---|
| N > 0 changed | any | ⚠️ **behind — N in-scope files** |
| 0 changed | any | ✅ **current**, even where the calendar says stale — nothing changed, so there is nothing to sync |
| not checked | within cadence | ✅ current *(by cadence)* |
| not checked | past cadence | ⚠️ stale *(by cadence)* |
| no fingerprint | any | ❌ never |

The second row is the one that earns this. A quiet source reading ⚠️ stale on the calendar while
being perfectly current is how a status column teaches people to ignore it — and the same
blindness in reverse is how a source sits 31 commits behind while reading ✅.

## Output

A short status table: source · last-synced · expected · **upstream** · status. Read-only — no
PR. Run it before relying on the repo for anything important, and as part of the scheduled agent
so a failed run is loud, not silent.
