# Unroutable brain content

Status: built
Reviewed: 2026-09-07 — needs revision (findings applied 2026-09-07)
Date: 2026-09-07

## Goal

A brain can hold content that routing will never open, and today nothing says so. A domain
declaring a kind no intent points at renders in the session map like any healthy domain.
`brain-routing` then never makes it a *candidate* — so it is neither loaded nor named in the
announce line's `skipped:` slot. The owner learns their content is unreachable only when
someone asks a question and gets nothing.

That last part is the precise failure. `SKILL.md` step 2 promises "skipping nothing silently"
and the announce line has a `skipped:` slot to honour it; both are bypassed, because the
domain never enters the set that either applies to.

After this ships, **a vocabulary miss announces itself at read time.** Whether the brain also
gets a way to recover from one without forking routing is the open scope question below —
the Goal deliberately does not promise it.

## Findings

The diagnosis, because it is the expensive part to reconstruct. Claims below are verified
against this repo except where marked otherwise.

### Labeling a domain is currently worse than not labeling it

Two ways a domain fails to route. Only the harmless one is guarded.

| | No `kinds:` declared | `kinds:` the router doesn't know |
|---|---|---|
| Manifest | lands in `unclassified[]` (`gen-manifest.sh:49-56`) | looks like any healthy domain |
| Session hook | prints `- unclassified: <path>` (`session-start.sh:65`) | prints `[billing] — cheap` |
| `/sync` | offers classify-and-confirm (`sync.md:45-50`) | nothing |
| Eval coverage | `routing/unclassified-visible` | none |
| Result | visible orphan | **silent** orphan |

`scaffold/setup/README.md` §1a already commits to "never silently" for the left column. The
right column has no such protection, so an owner who did the responsible thing and labeled
their domain gets the quieter failure.

Nothing validates a declared kind anywhere: `gen-manifest.sh` passes the string through
untouched, the hook prints whatever it finds, and `/sync` triggers only on the `unclassified`
list. `tests/gen-manifest.test.sh:34` already passes with `kinds: [edge-case]`.

**The real case is not a per-domain binary.** A domain can declare
`kinds: [product-principles, billing]` — routing fine via the first kind while the second is
dead. Such a domain is not an orphan, but it still contains a vocabulary miss. Any warning
therefore has to be **per unknown kind, not per domain**, which decides the hook's output
shape and its test.

### The check is derivable; the vocabulary is not

Verified: the union of `intents.json`'s values is exactly the 20 kinds documented in
`synapse/routing/README.md` (21 once the pricing-kind PR, `feat/pricing-model-kind`, lands; this document uses **20 as the baseline**,
since that is what `main` holds). That correspondence is structural, not luck — a kind no
intent points at is unroutable whether or not a catalog table lists it.

So **the check needs no new list and cannot drift**: it is a set difference against something
synapse already ships. Note the heading's limit — the *check* is derivable; the *vocabulary
itself* is still hand-maintained in two places (`routing/README.md` and `setup/README.md`
§1a), and the pricing-kind PR had to touch both.

The check belongs in the hook rather than `gen-manifest.sh`, but not for the reason first
supposed. §12 forbids vendoring the **intent table**; the kinds list is *already* vendored
into every brain as prose in `setup/README.md` §1a, which is a `runtime.bump` path. The real
reason is staleness: a brain-local copy updates only by `/upgrade` PR, so a check there
starts false-alarming the moment the plugin's vocabulary grows and the brain hasn't upgraded.
The hook always runs the current plugin's table.

One cost this imposes. The hook does not read `intents.json` today. It can — `hooks.json`
passes `CLAUDE_PLUGIN_ROOT` — but it is dependency-free and must parse with grep/sed/awk.
That makes `intents.json`'s one-intent-per-line layout **a parsing contract**, the way
`gen-manifest.sh`'s output already is ("OUTPUT FORMATTING IS A CONTRACT"). Nothing in
`routing/README.md` says so today. Whoever builds this writes that constraint down, or the
first person to pretty-print the file breaks the warning silently.

### Kinds are per-domain; files are per-file

*Observed in a real brain (a subscriber brain) and not reproducible in this repo — the specifics below
are reported, not verified here. The structural point does not depend on them.*

Three files sit inside a domain whose declared kinds are correct for the domain and wrong for
those files — three pricing and UX files
inside a `product/` domain declaring `product-principles` and `product-roadmap`.

That domain is in the `expensive` band, and the band gate (`SKILL.md:34-36`) reads:

> **expensive** — direct match only — not even an index peek on an unmatched-but-plausible
> domain, that's for cheap/normal only

So the one fallback that would have surfaced those files is switched off for exactly the
domains large enough to contain surprises. Growing the vocabulary cannot fix this: no
vocabulary makes a domain-level tag describe file-level contents.

### The same brain's other orphans

*Also reported, not verified here.* Two domains with zero kinds — `context/canon/company`
(mission, north star, org design, operating principles) and `context/derived/<docs domain>`. Both
are correctly visible as unclassified today. Neither has a home in the 20-kind vocabulary.

Note the ordering trap: stamping a not-yet-real kind on them would *remove* them from
`unclassified[]` and convert a visible orphan into a silent one. Tagging ahead of the router
is only safe once vocabulary misses are loud.

## Non-goals

- **Per-brain routing rules.** A brain never authors or extends routing locally.
  DESIGN.md §12's corollary; the whole point of the central table.
- **Replacing the closed vocabulary with open/semantic routing.** The closed set is what makes
  `synapse/evals/routing/*` possible — open routing has no regression surface. Any escape
  hatch composes with the table as a floor, never replaces it. (This constrains candidate C
  below; see the tension noted there.)
- **Fixing the audited brain's tagging.** Brain-side follow-up. **Not yet tracked anywhere** —
  no issue exists.

## Decisions

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| How to proceed on the general mechanism | Write the spec, build nothing; decide scope after a critic pass | The candidate layers differ a lot in blast radius; scope is the real open question and deserves review before code | Shipping the hook warning this session |
| The immediate pricing gap | Grow the vocabulary now, as its own PR, independent of the larger design | Unblocks the live brain regardless of what the mechanism turns out to be | Bundling the unblock into a larger change and leaving the brain silent until it lands |
| Kind naming for pricing content | `pricing-model`, not `billing` | The content is pricing strategy, not invoicing mechanics | `billing` as the kind name; a rename is cheap only until a brain stamps its `_index.md` |
| Scope of the mechanism | Candidates **A** (hook warning) and **B** (index-peek band fix) | Between them they cover both failure modes, and neither touches the manifest schema or needs a migration for existing brains | C (`summary:`) and D (`/propose-kind`) for now — C until its open/semantic-routing tension is settled, D until its placement and eval ownership are designed |

Opened against the second row: **the pricing-kind PR** — a pricing kind, one intent, catalog-table and doc
updates, a regression eval case, and both plugin version bumps. **Open, not merged.**

## Open questions

Everything below is a recommendation, not a decision. None of it has been agreed.

### Scope — which candidates to build

Four, independent of each other. A, B and D are consistent with the stated architecture; C is
contested.

- **A. Loud warning (hook).** The hook diffs declared kinds against `intents.json`'s value
  union and prints each unknown kind. No brain changes, no schema change.
  *Cost:* `session-start.sh`, a synapse version bump and republish (CONTRIBUTING rules 2 and
  3 — `synapse/**` is published behaviour), the `intents.json` parsing contract written into
  `routing/README.md`, and a test. `tests/synapse-hook.test.sh:50` already builds a fixture
  with `kinds: [legal]`, an out-of-vocabulary kind — the test is half-written.

- **B. Index-peek band fix (skill only).** Gate the *peek* on `indexTokens` and the *full
  read* on total `tokens`, so an unmatched domain's `_index.md` — which already carries a
  per-file `| doc | what |` table — is readable at any band, while full reads stay gated as
  they are. This is the only candidate that addresses file-level strandedness.
  *Cost:* `SKILL.md` and a synapse bump. **No schema change** — the skill reads the manifest
  directly and `indexTokens` is already emitted (`gen-manifest.sh:86-88`).
  *Caveat:* that split exists for honest token accounting (schema 1 under-reported by ~10k
  tokens in a real brain), not as a peek gate. The affordance is real; the original intent
  was different.

- **C. `summary:` escape hatch.** An optional per-domain one-line description in `_index.md`
  frontmatter, emitted into the manifest and printed in the map, giving the reader something
  to match on when no kind fits.
  *Cost:* manifest schema bump (2→3), `gen-manifest.sh`, the hook, `SKILL.md`,
  `setup/README.md` §1a, and an `/upgrade` path for existing brains.
  *Tension:* this repo's own Non-goals reject open/semantic routing for having no regression
  surface, and a free-text field the reader matches against is exactly that. The defence is
  that `title:` already plays this role — the hook prints it, and the cheap band already
  permits "clear topical adjacency" — making `summary:` title-plus rather than a new
  category. That defence has to be accepted explicitly or C should be dropped.

- **D. `/propose-kind`.** Emits the Brainforge-side PR — intent, catalog rows, eval case,
  version bump — from the brain that needs it. Fires at authoring time as well as read time;
  today `/sync`'s classify-and-confirm can only offer existing kinds and has no way to say
  "the catalog is wrong here."
  *Undefined:* (1) where it lives — a brain-vendored command via `runtime.bump`, or a synapse
  command; those are different layers under §12. (2) Who runs the evals. `routing/README.md`
  mandates a passing `claude plugin eval` run for every `intents.json` change, and a PR
  generated inside a brain cannot run Brainforge's suite — so either it emits a
  by-definition-unmergeable PR, or someone Brainforge-side owns that step.

**Resolved: A + B.** C and D remain unbuilt; their open points above stand as written for
whenever they are picked up.

### Others

- **Two pre-existing routing weaknesses, now measurable.** Surfaced once
  `synapse/evals/routing-smoke.sh` could actually score absence assertions. Neither is caused
  by this spec's changes; both were previously invisible.
  1. *`no-tracker-reads` fails, consistently.* Writing a launch email, the reader opens the
     expensive `tracker/` domain, which the case asserts it must not. Failed on **3 of 3**
     runs, and **A/B confirms it is not a regression from the two-level band gate** — it fails
     identically against the pre-change `SKILL.md`. So: stable, reproducible, real token cost,
     no owner yet. This is the one to fix first — it is measurable and not flaky.
  2. *The announce line is unreliable.* Across runs of the same prompt with identical flags it
     is sometimes emitted and sometimes omitted, though `SKILL.md` says never to omit it.
     Demonstrated: `build-prototype` FAILED this grader on one full-suite run and PASSED it on
     the next, with no code change in between; `stranded-file` did the same across two runs.
     Suite totals moved 5/7 -> 6/7 on that basis alone. Any fix needs repeated runs to
     evaluate, which is exactly what the smoke runner cannot give cheaply and the real
     harness can.
  Both need a routing-behaviour fix of their own, not a vocabulary or gate change. Unresolved.

- **The pricing glossary and the UX patterns file are resolved** (2026-09-07):
  `pricing-model` and `ui-build-standards` respectively. Billing at this org is a product
  surface — the software people use to manage an account and subscribe — not back-office
  operations, so it sits with pricing rather than needing an invoicing kind. Noted for
  whoever next reads the vocabulary: the kind name `pricing-model` is therefore narrower than
  what it covers; the intent string ("pricing, packaging, or billing") is what carries the
  routing.


- **No eval covers the subscribed-reader path, which is where the peek actually matters.**
  Every case in `synapse/evals/routing/` scaffolds the brain as the working directory, so the
  reader gets `brain-manifest.json` — including `files[]`, which already carries per-file
  titles. Two fresh-context readers confirmed a stranded file is now reachable, but one got
  there by peeking `tracker/_index.md` and the other straight from `files[]`, never opening
  the index. A **subscribed** reader sees only the hook's map, which prints domain lines with
  no file list at all — that is the case where the index peek is the *only* route to a
  stranded file, and nothing tests it. Building it needs a scaffold that runs the hook with
  `SYNAPSE_BRAINS`; no existing case does. Unresolved.


- **Whether the pricing intent should also collect `positioning`.** The pricing-kind PR ships a
  single-kind intent, unlike every other row in the table. Adding `positioning` would make
  pricing questions also open brand domains in every subscriber's brain. Left out as
  unjustified cost on an assumption. Unresolved.

- **What vocabulary `context/canon/company` needs.** Mission, north star, org design and
  operating principles have no home in the current 20. Possibly `company-principles` and/or
  `org-design`; possibly `product-principles` is close enough and the domain should be
  re-scoped. Not designed. Unresolved.

- **When may the audited brain stamp `company/_index.md` and the docs domain `_index.md`?**
  Recommendation: stamp anything mapping to an existing kind now (the brand-voice pointers in
  a derived docs domain qualify); hold anything needing new vocabulary until candidate A ships,
  because stamping early trades a visible orphan for a silent one. Unresolved — question was
  asked and not yet answered.

## What shipped

- `synapse/hooks/session-start.sh` — warns per unroutable kind, naming the kind and the domain
  that declares it. Vocabulary derived from `intents.json`'s value union; skipped silently if
  that file is unreadable; hook still always exits 0.
- `synapse/routing/README.md` — the one-intent-per-line parsing contract, and the corollary
  that a kind no intent points at is a dead word.
- `synapse/skills/brain-routing/SKILL.md` — band gate split into index peek (any band) and
  full read (gated as before); new step 4 treats a flagged unroutable kind as a peek signal.
- `evals/fixtures/acme-brain` — `tracker/vendor-contracts.md`, a file the expensive tracker
  domain's `project-tracking` kind does not cover, plus its `_index.md` row and manifest entry.
- `synapse/evals/routing/stranded-file/` — eval for the peek.
- `tests/synapse-hook.test.sh` — asserts the warning fires for an unknown kind, names the
  domain, does not fire for a healthy brain, and warns per kind rather than per domain.
- `synapse/.claude-plugin/plugin.json` — 0.3.0 → 0.4.0. `.claude-plugin/plugin.json` unchanged:
  no `runtime.bump` path touched.

## Where it diverged

Two things.

**The branch was restacked.** It began on `main` and was rebased onto `feat/pricing-model-kind`
(the pricing-kind PR) mid-build: both otherwise bump `synapse` to 0.3.0 and edit `routing/README.md`, so
they would have collided. This branch therefore lands *after* the pricing-kind PR and bumps to 0.4.0.

**Candidate B has no executed verification.** Its behaviour lives in `SKILL.md` prose, so the
only real proof is the eval, and `claude plugin eval` is gated behind org-level early access on
this machine. Candidate A is covered by `tests/synapse-hook.test.sh`, and that coverage was
mutation-checked — disabling the hook's vocabulary lookup makes the suite fail with
`FAIL: unroutable kind not announced`, so the assertion is real rather than vacuous. B has no
equivalent. Treat the peek behaviour as unverified until the evals run.

## Plan

### Step 1 — Hook warns per unroutable kind

Files: `synapse/hooks/session-start.sh`
Change: after the domain lines and the `unclassified` block, derive the routable vocabulary as
the union of `intents.json`'s values (`${CLAUDE_PLUGIN_ROOT}/routing/intents.json`, falling
back to `$(dirname "$0")/../routing/intents.json` so direct invocation works in tests). Emit
one line per *kind* — not per domain, so a domain declaring one good kind and one bad kind
still warns — naming the kind and the domain that declares it. Dependency-free: grep/sed/awk
only. Skip silently if `intents.json` is unreadable; the hook always exits 0.
Verify: `bash tests/synapse-hook.test.sh` → PASS, with the new assertion in step 6.

### Step 2 — Write down the parsing contract

Files: `synapse/routing/README.md`
Change: state that `intents.json`'s one-intent-per-line layout is a parsing contract, because
the dependency-free session hook reads it with sed to derive the vocabulary. Mirrors the
existing contract note in `gen-manifest.sh`.
Verify: read by eye.

### Step 3 — Split the band gate into peek and full read

Files: `synapse/skills/brain-routing/SKILL.md`
Change: rewrite step 3 so an **index peek** is permitted at any band on any plausibly relevant
domain — including one whose kinds did not match, or that declares none — because `_index.md`
costs `indexTokens`, which the manifest reports separately from total `tokens`, and its
per-file doc table is the only place a file its domain's kinds don't cover can be found. Full
reads stay gated exactly as they are. Add: treat a kind the map flags unroutable as a signal
to peek.
Verify: read by eye; behaviour covered by the eval in step 5.

### Step 4 — Fixture gains a stranded file in an expensive domain

Files: `evals/fixtures/acme-brain/context/derived/tracker/vendor-contracts.md`,
`evals/fixtures/acme-brain/.brainforge/brain-manifest.json`
Change: add a file to the `expensive` tracker domain on a topic `project-tracking` does not
cover, and register it in the manifest. Keep the manifest's existing schema-1 shape and the
single-line file-object formatting contract.
Verify: `python3 -c "import json;json.load(open(...))"` parses, and
`bash tests/synapse-hook.test.sh` still passes.

### Step 5 — Eval case for the peek

Files: `synapse/evals/routing/stranded-file/case.yaml`, `.../scaffold.sh`
Change: prompt asks about vendor contracts. Assert the model reads `tracker/_index.md` despite
no kind match, then reads `vendor-contracts.md`, and emits the announce line.
Verify: `claude plugin eval ./synapse --eval-dir evals --case 'stranded-file'` — **gated behind
org-level early access; expected to be unrun here and flagged in the PR.**

### Step 6 — Hook test asserts the warning

Files: `tests/synapse-hook.test.sh`
Change: the collision fixture already declares `kinds: [legal]`, an out-of-vocabulary kind.
Assert the hook names it unroutable. Add a domain declaring one good and one bad kind, and
assert only the bad one is named.
Verify: `bash tests/synapse-hook.test.sh` → PASS.

### Step 7 — Version bump

Files: `synapse/.claude-plugin/plugin.json`
Change: bump `version` (published behaviour changed — CONTRIBUTING rules 2 and 3).
`.claude-plugin/plugin.json` does **not** bump: no `runtime.bump` path is touched.
Verify: `git diff --stat` shows no `scaffold/` changes.
