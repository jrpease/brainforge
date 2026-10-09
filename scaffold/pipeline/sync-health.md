# Playbook: sync health

Makes staleness **visible** so nobody trusts silently-broken truth.

Staleness is a fact about the upstream source, not about the calendar. Where the real answer is
free, take it. Fall back to cadence only where it is not, and always say which one you used.

## Checks

1. **Upstream reality — run this first.** For each source type with an `enabled` entry, run its
   gate script once, with no ids: `bash .brainforge/gate-<type>.sh` (`repos` → `github`,
   `websites` → `website`, any other key is its own name). It is the same gate `/sync` runs
   before every sync: no LLM, no tokens, and it never writes `.sync-state.json`. It prints one
   JSON line per enabled entry (`.brainforge/README.md` § Gate scripts). For a repo, it diffs
   `lastSha..origin/<branch>` on the **fetched ref** and filters it through the source's
   `.brainforge-source.yml` (`adapters/github.md` §0a-bis, §0b). The registry's `summarize` is
   applied at extraction, not by the gate, so N can include paths the registry leaves out.

   The upstream column reads each line's `status`:
   - `changed` → **N changed**, where N is the length of `delta` (in-scope files for a repo, URLs
     for a site, dates for GA, fingerprint fields for Monday). Figma's gate reports a file-level
     change with an empty `delta`, so it reads **changed**, with no count. Never report or name
     `excluded`: those paths are out of scope.
   - `unchanged` → **0 changed**. Zero is an answer, not a failure.
   - `never` → **never synced**.
   - `blocked` → **blocked (<reason>)**. The gate refused to look, for example the clone points at
     a different repo.
   - `not-checked` → **not checked (<reason>)**.

   A gate that cannot run is reported as `not checked` **with its reason**. Never skip it
   silently, never guess the number, and never run the adapter's §1 by hand instead:
   - `not checked (no clone)` — the entry has no `localClone` and this adapter needs one.
   - `not checked (no credentials)` — the gate needs auth that is not in `.env`.
   - `not checked (offline)` — the fetch or API call failed.
   - `not checked (gate failed)` — the script is missing, exited non-zero, or printed no line for
     that entry.

   Built-in types: `figma`, `ga`, `github`, `monday`, `website`. Any other type is a custom adapter that ships no gate script; it runs its
   own §1 as written, because that is its only gate.

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
| `changed` (N in `delta`) | any | ⚠️ **behind — N changed** (figma: ⚠️ **behind**) |
| `unchanged` | any | ✅ **current**, even where the calendar says stale — nothing changed, so there is nothing to sync |
| not checked | within cadence | ✅ current *(by cadence)* |
| not checked | past cadence | ⚠️ stale *(by cadence)* |
| `blocked` | any | ⚠️ **blocked — <reason>**: ask the owner |
| `never`, or no fingerprint | any | ❌ never |

The second row is the one that earns this. A quiet source reading ⚠️ stale on the calendar while
being perfectly current is how a status column teaches people to ignore it — and the same
blindness in reverse is how a source sits 31 commits behind while reading ✅.

## Output

A short status table: source (its `label`, else its `id`) · last-synced · expected · **upstream** · status. Read-only — no
PR. Run it before relying on the repo for anything important, and as part of the scheduled agent
so a failed run is loud, not silent.
