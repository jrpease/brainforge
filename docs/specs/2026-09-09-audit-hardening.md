# Audit hardening

Status: built
Date: 2026-09-09

## Goal

An outside audit of a subscriber brain, on 2026-09-08, found seven things. Six of them are ours,
filed as six issues in a tracker that has since been closed, so **this document is the durable
record of the diagnosis**, not a pointer to one. They are not six unrelated bugs. Five of them are the same
bug wearing different clothes: **the brain reports on itself using a proxy for reality instead
of reality.** A commit sha standing in for content. A calendar standing in for upstream
change. A prose note standing in for an enforceable rule. Each proxy was cheaper to build and
each one is now wrong in a way nobody can see.

After this ships, four checks that currently guess stop guessing:

1. The map's staleness warning fires when the map is stale, and not otherwise.
2. Content that routing cannot reach is findable by asking, not only by getting a wrong answer.
3. `/sync-health` reports what changed upstream, not how many days elapsed.
4. A source repo can declare what must never be summarized, in the repo, where its owners live.

## Findings

Verified in this checkout unless marked otherwise. The diagnosis is the expensive part to
reconstruct, so it goes here rather than in a commit message.

### 1. The staleness warning cannot ever turn off, and the proposed fix doesn't fix it

Reproduced on a synthetic brain at `main` (a commit that predates the repo merge): scaffold a brain, commit content, run
`gen-manifest.sh`, commit the manifest, run the hook. Output:

```
🧠 brain — brain at …/home/brain (last change 2026-09-09, map generated 2026-09-09)
   ⚠ map predates the latest change — for detail, trust domain _index.md files over the map.
```

The map was generated seconds earlier. `gen-manifest.sh:31` stamps `HEAD`; committing the
manifest moves `HEAD`; `session-start.sh:51` compares the two. The staleness finding has this right.

**What the staleness finding's recommendation gets wrong.** It proposes comparing against the last commit that
touched content (`git log -1 --format=%H -- context`), warning only when `generatedFrom` is an
ancestor. Tested against the flow `/sync` actually prescribes, where the derived change and the
regenerated manifest land in **one** commit (`sync.md` § "Regenerate the manifest (always,
before the PR)"):

```
generatedFrom stamped   : 419c689d62da437d0f65612b211a1d838f68deac
git log -1 -- context   : 6e87358ace83995406902c7e22bdacd1fd7c4b91
==> proposed fix STILL WARNS FOREVER (generatedFrom is the parent commit)
==> ancestor rule warns too
```

The self-reference is the whole problem, and no commit sha escapes it: the sha of the commit
carrying the manifest cannot be known while writing the manifest. That is the same reason
the finding correctly rules out a CI step. It rules out its own first recommendation too, and the
finding should be updated to say so before anyone spends a day on it.

**Correction, 2026-09-09 (post-audit).** I over-generalised that last point in the first draft
and repeated it in five places. "A CI step cannot work" was true *of the sha scheme*. It is
false of the fingerprint scheme, and the difference matters: a post-merge job that regenerates
and commits touches only `.brainforge/`, so the context tree is unchanged and the fingerprint
still matches. Verified. That is not a footnote — CI regeneration is now the clean fix for the
conflict two concurrent PRs always produce on `brain-manifest.json`, and leaving the wrong
claim standing would have stopped the next person doing the right thing.

**What does work** is the finding's own second suggestion, a content hash. Git already computes one:
the **tree object id** of the context root. Verified:

| | worktree tree-oid | `HEAD:context` |
|---|---|---|
| after commit | `71c488ee…` | `71c488ee…` |
| dirty worktree | `2a385108…` | `71c488ee…` |
| content + manifest in one commit | `2a385108…` | `2a385108…` |
| fresh clone of the above | — | `2a385108…` |

Ignored files are excluded, untracked-but-not-ignored files are included, and it survives
rebases. The reader side is one `rev-parse`, no file hashing.

### 2. The coverage check cannot live in `/drift`

The coverage finding nominates `/drift` or `/sync-health`. Both are brain-resident commands, and the join
needs `intents.json`, which DESIGN §12 and `routing/README.md` forbid vendoring into a brain
("Never vendor it into a brain"). The 2026-09-07 unroutable spec already worked out why: a
brain-local copy updates only by `/upgrade` PR, so it starts false-alarming the moment the
plugin's vocabulary grows and the brain hasn't upgraded.

So the check goes in synapse, where the hook already derives the vocabulary from the live
intent table. That is a correction to the finding, not a disagreement with it.

Of the coverage finding's three checks, one already ships. The hook warns per unroutable kind (shipped
2026-09-07). Check 2, an unreachable domain, is mostly covered: a domain with no kinds lands in
`unclassified[]` and a domain whose kinds are all dead draws one warning per kind. **Check 3 is
the gap, and it is the exact shape of the audit's bug**: one narrow intent gating a large block of tokens
including the only accurate doc on its subject in the brain.

Check 3 is also the only one that changes read-time behavior rather than just reporting. An
expensive domain behind a single intent is a domain the band gate opens for one phrasing and no
other. The reader should treat it the way it already treats a flagged unroutable kind: peek the
index. That makes it a map line, not just an audit line.

### 3. `sync-health` already has the primitive and doesn't call it

The upstream-reality finding is right and the detail worth keeping is that this costs nothing. The GitHub adapter's
step 1 runs `git fetch` plus `git diff <lastSha>..origin/<branch> --name-only` before every
sync. `sync-health.md` resolves a cadence and compares dates. One of those is a fact.

The inverse failure matters as much as the reported one: a quiet source reads ⚠️ stale on the
calendar while being perfectly current, which trains people to ignore the column.

### 4. The scope rule sits on the wrong side of the boundary

The source-scope finding. A large set of
interview files under `calls/` and one key per named design partner under `partners/` are kept
out of shared context by a `$note` string in `sources.json`, in a repo their owners can only
read. The scope decision is right; its durability is not.

One thing the finding leaves implicit that the build has to decide: what happens when the declaration
is malformed. Falling back to registry scope would mean a typo silently reopens `calls/`. A
protection mechanism that fails open is not one.

## Non-goals

- **Federation.** The configurable-root finding's read is "not now, but not never." Only its one-line half ships
  here: a configurable context root, so a repo whose docs don't live under `context/` can emit a
  valid manifest. No multi-brain routing, no pilot, no ownership-at-runtime.
- **The source-side GitHub Action trigger** (the upstream-reality finding's related ask). Roadmapped, not built. See
  Open questions.
- **Fixing the audited brain.** Brain-side follow-up. The unit intent's kind is already tagged there;
  this ships the half that routes it.
- **Candidates C and D** from the 2026-09-07 unroutable spec (`summary:` frontmatter,
  `/propose-kind`). Untouched, their open points stand as written.

## Decisions

Rows sourced from the findings are the maintainer's written positions on them. Rows sourced from this
build are calls made to ship it, each forced by a Finding above.

| Decision | Chose | Why | Rules out | Source |
|---|---|---|---|---|
| Fix the staleness finding by comparing what? | The git tree oid of the context root, stamped as `contextFingerprint` | The only mechanism that survives content and manifest landing in one commit (Finding 1) | Every commit-sha variant, including the finding's own recommendation and a CI regeneration step | This build |
| Manifest schema | Bump 2 → 3, additive: `contextRoot` + `contextFingerprint` | Line format and arithmetic unchanged, so grep/sed/awk consumers keep working; the number documents the contract change | A silent field addition that readers can't detect | This build |
| Behavior on a pre-schema-3 map | One actionable line naming the command that clears it | Staleness is unknowable without the field; a warning that self-clears on resolution is the sync-health gate's pattern, not the drift gate's | Silently skipping the check; keeping the broken HEAD comparison as a fallback | This build |
| Where the coverage check lives | synapse, as `routing/coverage.sh`, with the hook and a new `/synapse:coverage` calling it | The join needs `intents.json`, which a brain must never vendor (Finding 2) | `/drift` and `/sync-health` as the home, as the finding proposes | This build (corrects the finding) |
| Which of the coverage finding's checks reach the always-on map | Unroutable kinds (already shipped) and narrow gates | A narrow gate changes what the reader should open, so it earns its ~15 tokens; the rest are audit findings, not read-time signals | Putting the full join in the map and re-creating the always-on-warning problem the staleness finding is about | This build |
| The unit intent | `"understanding another team's product or unit context": ["unit-context"]` verbatim | The kind is already tagged brain-side; this is the second half of a done fix | Overloading `user-archetypes` permanently | Unit-intent finding |
| In-repo scope declaration | `.brainforge-source.yml`, subtractive-only | Boundary travels with the repo, gets reviewed in the owner's PRs, scales past what one person remembers | Registry-only scope; any mechanism that can widen scope | Source-scope finding |
| Malformed `.brainforge-source.yml` | Stop and ask. Never fall back to registry scope | A protection that fails open isn't one; a typo would silently reopen `calls/` (Finding 4) | Best-effort parsing, ignore-and-continue | This build |
| What `sync-health` reports | Real upstream delta where it is free, cadence only as the fallback, and `not checked` named with its reason | Turns the table from a guess into a fact at zero token cost (Finding 3) | Cadence as the primary verdict; silently defaulting to the calendar when the gate can't run | Upstream-reality finding |
| Configurable-root scope | Configurable context root only | "Not now, but not never" | Building federation on an audit finding | Configurable-root finding |
| Where the work lands | A branch on the repo, merged after review | Reviewed like any other change | Editing main directly | This build |

## Open questions

- **Should the narrow-gate line be in the always-on map at all?** I put it there because it
  changes what the reader opens, not just what the owner should fix. The risk is the staleness finding's disease:
  a warning that fires on a domain whose shape is deliberate, every session, forever. It is
  rarer than the old staleness warning (it needs `expensive` **and** a single intent) and it is
  silenced by the owner adding a second intent, which is the right fix anyway. Watch it on a
  real brain before deciding it stays. Unresolved.
- **The source-side trigger** (the upstream-reality finding's related ask): the audited team runs a GitHub Action that opens a sync
  issue on the brain when in-scope paths change. I'd take it — it also unpicks the coupling
  where a source's freshness depends on a clone path on one laptop. Not built here because
  shipping an unproven workflow template cuts against the live-proof bar in CONTRIBUTING, and
  the cross-repo issue-open auth is undesigned. Roadmapped. Unresolved.
- **Federation and a pilot** (configurable-root finding). The reasoning is sound and the marginal cost is
  genuinely lowest at the audited team. The thing to think hardest about is the one the finding names: federation
  makes "which brain owns this fact" a runtime question rather than a curation-time one.
  Roadmapped, not scheduled. Unresolved.
- **Does `/drift` still want a coverage line?** The check lives in synapse now, but `/drift` is
  where an owner goes to reconcile the map against reality, and it could print "run
  `/synapse:coverage`" when it sees an unclassified domain. Cheap. Not built. Unresolved.
- **Whether `never-summarize` should apply to non-repo adapters.** Figma, Monday and GA have no
  repo to carry the file. A Figma file could carry the same declaration in a page or a variable,
  but nobody has asked for it. Left out. Unresolved.

## What shipped

**Staleness.** `scaffold/.brainforge/gen-manifest.sh` stamps `contextRoot` and
`contextFingerprint` (the git tree oid of the context root, read from the working tree through a
throwaway index) at `"schema": 3`; `generatedFrom` is kept as provenance and nothing compares
against it. `synapse/hooks/session-start.sh` compares fingerprints, and says so distinctly when a
map is pre-schema-3 rather than pretending it can tell.

**Coverage.** `synapse/routing/coverage.sh`, a dependency-free awk join over `intents.json`
and a manifest. Four findings: orphan kinds, unreachable domains, narrow gates, and the intents a
brain cannot answer. The hook calls it in `--map` mode so the join has one implementation;
`synapse/commands/coverage.md` is the full report, with a table naming who owns each fix.

**The unit intent.** `synapse/routing/intents.json` (verbatim from the finding),
`synapse/routing/README.md` vocabulary, `scaffold/setup/README.md` §1a catalog row plus a
paragraph on why a unit kind is not an overloaded company kind, an Orion unit domain in
`evals/fixtures/acme-brain` declaring **only** `unit-context`, and
`synapse/evals/routing/unit-context/`.

**Source-declared scope.** `scaffold/pipeline/adapters/github.md` §0b defines
`.brainforge-source.yml` and its force order, and §1 now filters the cheap gate's file list
through it before anything is read. `scaffold/pipeline/README.md` carries the why.

**Upstream reality.** `scaffold/pipeline/sync-health.md` and
`scaffold/.claude/commands/sync-health.md`: an `upstream` column, a verdict table where reality
beats the calendar, and `not checked` always carrying its reason.

**Configurable root.** `BRAIN_CONTEXT_DIR` in the generator, recorded in the manifest so a
reader never assumes it. Federation itself roadmapped, not built.

**Migration and packaging.** `scaffold/.brainforge/README.md` documents schema 3 and the
fingerprint contract; `commands/upgrade.md` §5a regenerates the map when the generator changed, so
an upgraded brain does not sit on a map the reader cannot check; `ROADMAP.md`
carries the two deferred items; brainforge 0.8.0 → 0.9.0, synapse 0.6.0 → 0.7.0.

**Tests.** `tests/routing-coverage.test.sh` is new. `tests/gen-manifest.test.sh` and
`tests/synapse-hook.test.sh` gained the schema-3, same-commit, content-changed, pre-schema-3 and
narrow-gate cases. All eight suites pass. Every new assertion was mutation-checked: reverting the
fingerprint to a sha, ignoring `BRAIN_CONTEXT_DIR`, disabling the narrow-gate check, and treating
every declared kind as routable each make the suite fail with the expected message.

## Where it diverged

Two things.

**A latent test fragility surfaced.** `tests/gen-manifest.test.sh`'s idempotency check compared
the manifest on disk against a fresh run, which only held because nothing had regenerated between
them. Inserting steps before it broke it. It now regenerates first, so it is order-independent.
Pre-existing, exposed rather than caused.

**The evals were not run.** `claude plugin eval` is gated behind org-level early access on this
machine, and `synapse/evals/routing-smoke.sh` costs real tokens per case. The `unit-context` case
is written, parses through the smoke runner's own path (ruby YAML), its regex graders compile, and
every content grader matches the fixture text — but nothing has executed the routing behaviour.
`routing/README.md` requires a passing eval run for every `intents.json` change, so **that
requirement is outstanding**, not met.

**Eval run (2026-09-11):** unit-context PASS via synapse/evals/routing-smoke.sh

## Round two — auditing the fix

Three read-only agents were pointed at the plugin after the first pass landed, on the reasoning
that production had just caught six things a fixture never would, so there were probably more.
Lenses: proxies-for-reality, convention-enforced contracts, and day-2-at-scale. Every finding
below was independently reproduced before being acted on.

**The audit's most useful result was catching four defects in the fix itself**, which is the
argument for running it at all.

### Mine, from the first pass

| | Fix |
|---|---|
| `BRAIN_CONTEXT_DIR` lived only in the environment, so `/sync`, `/upgrade` §5a and the README all silently reverted the root and emitted a zero-domain map | Generator reads the root back from the committed manifest when the env var is unset |
| "Empty fingerprint means not computable" could never happen — `git rev-parse` prints an unresolvable argument to **stdout** and fails only by exit code, so `\|\| true` captured junk and turned *unknown* into *stale* | `--verify -q` on both sides |
| `coverage.sh` reported a zero-domain map as clean, vacuously — the second check that should have caught the root bug | Zero domains is now a finding, exit 1, and `--map` surfaces it while keeping its exit-0 contract |
| One untracked file under the context root re-armed the permanent staleness warning through a side door, from a state only one laptop can see | The generator names untracked files it folded into the fingerprint, at the one moment they can be fixed |
| **The narrow-gate warning fires by construction.** 21 of 24 kinds are single-intent and all five adapters *mandate* one, so every expensive adapter-emitted domain would warn forever. My open question claimed an owner could silence it by adding a second intent — they cannot, DESIGN §12 forbids brains authoring routing | Demoted from a ⚠ line to a `· single-intent` marker on the domain line: same signal to the reader, ~3 tokens, no implied defect, nothing to "fix" |
| **"No commit sha works, and that also rules out CI"** — the second clause was over-generalised from the first and repeated in five places including the finding text | Corrected everywhere. A post-merge CI job touches only `.brainforge/`, so the context tree and the fingerprint are unchanged. Verified |

### Pre-existing

| | Fix |
|---|---|
| The drift gate — the roadmap's flagship — goes **silent forever** once its watermark commit is unreachable, which a squash-merge guarantees. Fails open, and looks identical to "reviewed, nothing changed" | Unreachable and empty watermarks are now distinct, loud lines |
| The session hook makes unbounded network calls: ~75s on a blackholed remote, past Claude Code's 60s hook default, so the hook is killed and **no** brain's map prints | Bounded `git` with a hand-rolled deadline (macOS has no `timeout`), `GIT_TERMINAL_PROMPT=0`, ssh `ConnectTimeout`, git's own first stderr line surfaced so offline / expired-credentials / repo-gone are distinguishable |
| Two clone states never self-healed: a directory with no `.git`, and a diverged mirror | Moved aside and re-cloned; reset to origin with a line saying so |
| `/upgrade` **resurrects a file the owner deleted**, on the second upgrade, against this command's own "Never" | `null` tombstone in the manifest; re-creating the file by hand clears it |
| The adapter only ever `fetch`es, then reads the **working tree** — so `.brainforge-source.yml` is invisible until someone pulls that clone by hand, and syncs get stamped at a sha whose content was never read | New §0a-bis: every read is `git show origin/<branch>:<path>`. Never the working tree |
| A credential embedded in `remote.origin.url` was committed verbatim into an artifact every subscriber clones | Userinfo stripped |
| Quoted or block-list `kinds:`, or `kinds:` below line 20, produced an invalid-JSON manifest or a false "unclassified" — hidden because every reader in this repo strips quotes | Frontmatter block parsed properly; all three YAML spellings accepted |
| The word-based token estimate under-reads JSON 1.6–3.7×, and the **band** the reader acts on comes from it | `.json` estimated by bytes/4 |
| A directory with content but no `_index.md` is invisible to the map while the fingerprint says the map is current | New `unindexed[]`, rendered in the map like `unclassified` |
| Every adapter declares a domain-total envelope that `ADAPTER-TEMPLATE.md` says "fires automatically" and `/sync` never checked | `/sync` checks it |
| `/sync`'s growth baseline used a fixed `/tmp` path — two brains on one machine compared against each other | `mktemp` |
| `derived/` is called a "synced mirror" in the always-on session map while golden rule 6 forbids producing mirrors — the map was teaching the mistake the rule exists to prevent | Reworded to "synced from source" |

### Roadmapped rather than built

Post-merge CI regeneration (now unblocked, needs the live proof), and a staleness signal for
authored canon — `DESIGN.md` §8 promises one from `last-reviewed` and nothing reads that field,
so `brand`, the domain with no derived counterpart, has no staleness signal at all. The
threshold is a judgement call, which is why it is not built here.

## Plan

### Step 1 — Content fingerprint and configurable root in the generator

Files: `scaffold/.brainforge/gen-manifest.sh`
Change: read the context root from `${BRAIN_CONTEXT_DIR:-context}` and use it everywhere
`context` is currently hardcoded (the `find`, the final count line). Add a `ctx_tree` helper
that computes the worktree tree oid of that root through a throwaway `GIT_INDEX_FILE`, leaving
the real index untouched. Stamp `"schema": 3`, `"contextRoot"`, and `"contextFingerprint"`.
Keep `generatedFrom` as provenance. Keep the output formatting contract byte-for-byte: 2-space
indent, one key per line, single-line file objects.
Verify: `bash tests/gen-manifest.test.sh` → PASS.

### Step 2 — Hook compares fingerprints, not shas

Files: `synapse/hooks/session-start.sh`
Change: read `contextRoot` and `contextFingerprint` from the manifest. Compare against
`git -C "$dir" rev-parse "HEAD:$root"`. Warn only on a real mismatch. When the field is absent
(schema ≤ 2), print one actionable line naming `bash .brainforge/gen-manifest.sh` instead.
Delete the `head_sha` comparison.
Verify: `bash tests/synapse-hook.test.sh` → PASS, including the new "healthy brain draws no
staleness warning" assertion.

### Step 3 — Routing coverage as a deterministic join

Files: `synapse/routing/coverage.sh` (new)
Change: dependency-free awk join over `intents.json` and a brain manifest. Two modes: `--map`
emits the hook's ⚠ lines (unroutable kinds, narrow gates); default emits the full report
(orphan kinds, unreachable domains, narrow gates, and intents this brain cannot answer). Exit 1
when there are findings, 0 when clean. Relies on both parsing contracts.
Verify: `bash tests/routing-coverage.test.sh` → PASS.

### Step 4 — Hook delegates to coverage.sh

Files: `synapse/hooks/session-start.sh`
Change: replace the inline vocabulary awk block with a call to `coverage.sh --map`, so the join
has one implementation. Skip silently if the script is unreadable. Hook still always exits 0.
Verify: `bash tests/synapse-hook.test.sh` → PASS; existing unroutable-kind assertions unchanged.

### Step 5 — `/synapse:coverage`

Files: `synapse/commands/coverage.md` (new)
Change: locate the brain the way `SKILL.md` §Locate does (map path, else cwd manifest), run
`coverage.sh`, print the report, and say plainly that a clean run means every domain is
reachable. Read-only.
Verify: run it against `evals/fixtures/acme-brain` and read the output.

### Step 6 — Skill treats a narrow gate as a peek signal

Files: `synapse/skills/brain-routing/SKILL.md`
Change: extend step 4 so a `⚠ narrow gate` line is handled like `⚠ unroutable kind` — peek the
index whenever the task is near the subject, and say so in the announce line. Update the
"map predates" ground rule to match the new warning text.
Verify: read by eye; behavior covered by the evals, which need the harness.

### Step 7 — `unit-context` intent, vocabulary, catalog, eval

Files: `synapse/routing/intents.json`, `synapse/routing/README.md`,
`scaffold/setup/README.md`, `evals/fixtures/acme-brain/context/derived/units/orion/*`,
`evals/fixtures/acme-brain/.brainforge/brain-manifest.json`,
`synapse/evals/routing/unit-context/{case.yaml,scaffold.sh}`
Change: add the intent verbatim from the unit-intent finding, add `unit-context` to the vocabulary list and the §1a
catalog table, add a fixture unit domain declaring **only** `unit-context` so the case cannot
pass through another kind, and write the eval.
Verify: `python3 -m json.tool` on the fixture manifest and `intents.json`;
`bash tests/synapse-hook.test.sh` → PASS. The eval itself needs `claude plugin eval` or
`routing-smoke.sh`; say which was run.

### Step 8 — In-repo source scope

Files: `scaffold/pipeline/adapters/github.md`, `scaffold/pipeline/README.md`
Change: new §0b in the adapter defining `.brainforge-source.yml` — `never-summarize` as a hard
exclusion, `summarize` intersected with registry scope, in-repo wins on conflict, re-read every
sync, fail closed on a malformed file, and the exclusion applied to the cheap gate's file list
before anything is read. Record in the PR body that a declaration narrowed scope, with counts
and no names. A short § in `pipeline/README.md` pointing at it.
Verify: read by eye. No executable surface to test.

### Step 9 — sync-health measures upstream

Files: `scaffold/pipeline/sync-health.md`, `scaffold/.claude/commands/sync-health.md`
Change: add the upstream check and an `upstream` column. Verdict rule: real delta wins,
cadence is the fallback, and an unrunnable gate is reported as `not checked` with its reason
(no clone, no credentials, offline). Calendar-stale with zero upstream changes is current.
Verify: read by eye.

### Step 10 — Docs, migration, versions

Files: `scaffold/.brainforge/README.md`, `commands/upgrade.md`, `ROADMAP.md`,
`.claude-plugin/plugin.json`, `synapse/.claude-plugin/plugin.json`
Change: document schema 3 and the fingerprint contract; add an `/upgrade` step that regenerates
the manifest when `gen-manifest.sh` changed, so upgraded brains don't sit on a schema-2 map;
roadmap the source-side trigger and the federation pilot as named items; bump brainforge
0.8.0 → 0.9.0 (scaffold and commands touched) and synapse 0.6.0 → 0.7.0 (plugin behavior).
Verify: `git diff --stat`; CONTRIBUTING's bump rules checked against the diff.
