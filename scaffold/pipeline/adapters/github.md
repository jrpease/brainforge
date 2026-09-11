# Playbook: sync a code repo  (built-in adapter)

The cheapest source — change detection is just local git. `GITHUB_TOKEN` from `.env` for
private-repo read access (read-only contents scope is enough).

## 0. Inputs
- `sources.json` → `repos[]`
- `.sync-state.json` → `repos[<id>].lastSha`

## 0a. Size envelope  — golden rule #6

| Emitted doc | Envelope |
|---|---|
| `repos/<repo-name>.md` | ≤ 2,500 each |
| `repos/_index.md` | ≤ 1,500 |
| **domain total** | **≤ 8,000** |

**Emit reference, not a file listing.** Directory *names* and counts, the stack table, the route or
page registry, key components, and what changed since the last sha. Never per-file inventories, never
source excerpts, never a dependency dump — a package manifest can carry well over a hundred entries
of which perhaps thirty define the stack. A repo holds thousands of files and the summary must not
scale with them: if a repo doc is growing with the codebase rather than with its architecture, the
extraction is wrong, not the envelope.

## 0a-bis. Read the FETCHED REF, never the working tree  — applies to every step below

This adapter only ever runs `git fetch`. It never pulls and never checks out, so the clone's
**working tree is whatever that laptop last happened to check out** — possibly months behind the
ref the cheap gate just diffed. Reading files from it produces the worst failure this pipeline
has: a sync recorded at today's `lastSha` whose content came from an old checkout, after which
the cheap gate correctly reports "nothing changed" for exactly the commits nobody read.

So every read in this playbook is from the ref:

```
git -C <clone> show     origin/<branch>:<path>      # file content
git -C <clone> ls-tree -r --name-only origin/<branch>   # structure
```

Never `cat <clone>/<path>`, never `ls <clone>/`, never a glob over the working tree. If you
catch yourself reading a path that starts with the clone directory, stop.

## 0b. Source-declared scope  — subtractive only

A source repo may carry a `.brainforge-source.yml` at its root: the **source owner's own**
declaration of what a brain may summarize. Read it on every sync, before the cheap gate, and
read it **from the fetched ref** (`git show origin/<branch>:.brainforge-source.yml`) — from the
working tree it is invisible until somebody remembers to pull that clone by hand, which is the
"one person remembering" failure this whole mechanism exists to remove. Never cache it into the
brain.

```yaml
# .brainforge-source.yml — this repo's scope for any brain that syncs it.
version: 1
never-summarize:
  - "calls/**"        # user interviews, named external customers
  - "partners/**"     # one key per named design partner
summarize:            # optional; intersected with the registry, never added to
  - "docs/**"
```

Rules, in force order:

1. **`never-summarize` is a hard exclusion.** A matching path is treated as if it does not exist
   in the source. Do not read it, summarize it, quote it, count it into a figure you publish, or
   name it — not in the derived doc, not in the PR body, not in a scratch note.
2. **It beats the registry, always.** A path in the registry's `summarize` *and* in
   `never-summarize` is excluded. Registry config cannot override a source's own exclusion.
3. **`summarize` here is intersected with the registry's, never unioned.** The declaration can
   only narrow scope, never widen it. That is the answer to the obvious objection — a source
   cannot use this to push content into a brain that did not ask for it.
4. **Filter the cheap gate's file list through 1–3 before reading anything** (§1). A change
   confined to excluded paths is not a change: report "nothing in scope changed" and stop.
5. **Fail closed.** If the file exists but does not parse, or declares a `version` this adapter
   does not know, **stop and ask the owner**. Never fall back to registry scope. A typo must not
   silently reopen a path somebody excluded on purpose.
6. **Say it happened.** When a declaration narrowed scope, the sync PR body carries one line —
   `source scope: .brainforge-source.yml excluded N path(s)` — the count, never the names.

No file → registry scope governs. Say that in the PR body too, so its absence is a recorded fact
rather than an assumption.

## 1. Cheap change gate (always)
```
git -C <clone> fetch --quiet
git -C <clone> diff <lastSha>..origin/<branch> --name-only
```
- Empty diff → **stop.** Nothing changed.
- **Filter the result through §0b before reading a single file.** What survives is the in-scope
  change list; its length is the number `/sync-health` reports. Excluded paths never enter it.
  Build the filter from the declaration rather than applying globs by eye — a 31-commit backlog
  runs to hundreds of lines and judgement does not scale over it:

  ```
  git -C <clone> diff <lastSha>..origin/<branch> --name-only \
    | grep -vE '^(calls/|partners/)'      # one alternation per never-summarize entry
  ```
- Empty after filtering → **stop.** Nothing in scope changed.
- Else → you have the exact list of changed files. Map them to affected areas
  (routes/pages, components, config, docs).

## 2. Extract only the delta
- **Structured first (deterministic):** regenerate the route/page list and component list from
  `git ls-tree -r --name-only origin/<branch>` (§0a-bis), filtered through §0b — no LLM needed,
  and no dependence on what this laptop has checked out.
- **Narrative pass (LLM, gated):** only for changed areas that need description ("what does this
  flow do"), keep it short and factual. A wrong word here becomes "truth" — be conservative.
- Write to `context/derived/repos/<repo-name>.md`: stack, routes/pages, key components, notable
  changes since last sync.
## 3. Finish
- Stamp `source` / `last-synced` / `generated-by`.
- Update `.sync-state.json` → `repos[<id>].lastSha = origin/<branch> HEAD`.
- In `.sync-state.json`, set `"synced": true` in `repos[<id>]` and `lastFullSync` to today
  (`YYYY-MM-DD`). Disarms the session-start sync-health tripwire, which stays lit while any
  source's `synced` is `false` or `lastFullSync` is `null`.
- The emitted `_index.md` frontmatter MUST include `kinds: [repo-summaries]`.
- Branch + PR.

## Reminder: the repo owns its own truth
This produces a *summary for cross-team consumption*. Repo-specific implementation detail stays
in the repo. Do not pull canon down into the repo — the repo should *reference* canon
(see `templates/`).
