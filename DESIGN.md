# Brainforge: locked design

This is the decision record from the founding design session. Each section is a resolved
branch of the design tree, with the reasoning preserved so future contributors understand
*why*, not just *what*.

**One line:** *The Claude-native way to build and operate a "product-org brain": a
tool-agnostic git repo of authored truth + synced facts that any LLM can read.*

The whole design is a generalization of a pattern already proven in production. This pattern
was extracted from a production brain built for SWEET, a design org; that live testbed is why
none of this is speculative. The guiding constraint, inherited from that work: **prove one
loop end-to-end before scaling: the #1 failure mode is a beautiful empty library nobody
filled.**

---

## 1. Form factor

**Generator that scaffolds a self-sufficient brain repo and vendors a thin, re-emittable
runtime.** Tooling upgrades (sync playbooks, commands) come down as regenerated files via PR.

- *Not* a pure generator (every brain would fork the logic at birth and rot: bug fixes never
  reach already-generated brains; that's duplication, which the architecture exists to kill).
- *Not* a pure runtime (would couple every consumer to Brainforge being installed/alive,
  betraying the "materialized files, not a live proxy" principle).
- The brain stays a self-sufficient git repo (zero external dependency); the *behavior* is
  versioned and upgradable. Like `create-react-app` scaffolding + bumpable `react-scripts`.

## 2. Cross-LLM strategy

**The brain artifact is tool-agnostic** (markdown + JSON in git, readable by any file-aware
LLM). **The builder + manager layer is Claude-first.**

- The brain being plain files *is* the cross-LLM strategy. It already works everywhere.
- The guided setup experience is where Claude shines and is hard to replicate elsewhere, so:
  **Claude is the author's tool; every LLM is a reader.**
- Rejected: per-platform builders (Cursor rules + GPT config + …): four scaffolds that drift
  out of sync, the exact disease this cures.
- **MCP** parked as the eventual *universal reader* (the no-git path for ChatGPT /
  non-technical teammates). Strictly additive; does not gate v1.

## 3. Topology

**One product-org brain, multiple domains**: not many brains.

- The functions in scope all orbit the *same* artifacts (the product, design system, codebase,
  metrics), so they belong in one brain, not disconnected ones.
- Domains are an **à la carte menu, not a mandate**: set up only what the team has. An R&D
  team might run eng + design only; a pre-product brand team might run brand + design.
- Splitting into separate repos / access tiers is a later concern. Start unified; design the
  seams (clean domain folders, per-domain owners) so splitting is easy later.

## 4. Domains (the out-of-box catalog)

A catalog of presets, each a pair: *(starter canon set) + (default sync adapter)*.

| Domain | Lean | Canon (authored) | Derived (synced from) |
|---|---|---|---|
| `brand/` | authored | voice, positioning, naming, messaging | none at launch (site copy later) |
| `product/` | mixed | principles, roadmap, PRD conventions | Jira / Monday |
| `design/` | mixed | design principles, art direction | Figma (tokens, components) |
| `eng/` | derived | architecture decisions, conventions | GitHub repos |
| `analytics/` | derived | metric / north-star definitions | GA |

This table is the product. Bounded, defensible, a straight generalization of that source
pattern.

## 4a. Canon authoring (fighting the empty-library failure)

**ingest existing material → interview to fill gaps → draft as `status: draft` → human
approves → only then it's canon.**

- Structure isn't the value; canon is, and Brainforge cannot *know* a company's voice.
- Turn blank-page paralysis into editing (10x easier). Bootstrap the first draft from real
  material (deck, site, PRDs, READMEs), interview only for gaps.
- **Hard guardrail:** Brainforge-drafted canon must be *loudly provisional*. A confidently
  wrong auto-draft that a human rubber-stamps is worse than an empty stub: it launders
  fabrication into "truth" that then propagates to every LLM. Brand is the dangerous domain
  (subjective, low source material); the derived-leaning domains are safer to bootstrap.

## 5. Sync adapters

**Prose-but-contractual.** An adapter = a markdown playbook filling a fixed skeleton +
a `sources.json` schema entry + a generated slash command.

- The six golden rules *are* the contract, inherited from that original production pipeline:
  1. **Work scales with the delta, not the corpus**: cheap change-detection gate first,
     expensive extraction only on what changed.
  2. **REST, not MCP** for sync: MCP is heavy/token-hungry, reserved for interactive work.
  3. **Deterministic extraction over LLM summarization** wherever possible.
  4. **Every sync lands via PR, never a direct write**: the human trust gate.
  5. **Always update provenance + state**: `source` / `last-synced` / `generated-by`
     frontmatter + the sync-state fingerprint.
  6. **Extraction produces reference, not mirrors**: a derived doc is what an LLM reasons
     *from*, never a replica of the source's records. Adapters declare an expected size
     envelope; a sync that grows a doc past it says so in the PR body.
- Ship `pipeline/ADAPTER-TEMPLATE.md` (the canonical skeleton: gate / extract / emit /
  provenance / command) + an `/add-adapter` scaffolder. Consumers extend by filling the
  skeleton, not reverse-engineering style.
- *Not yet*: a declarative spec language or executable plugins. Premature; prove the path in
  prose first.
- **Built-in adapters:** Figma, GitHub, Jira, Monday, GA.
- **Shopify = the documented extension example**: already built to solve a real e-commerce
  integration need, then re-added via `/add-adapter` to prove the extension path is real, not
  aspirational.

## 6. Distribution & intent

**Build for A, package as B, defer C.**

- **(A) internal tooling: done.** Built by extracting from the same production brain built
  for SWEET (a real, live testbed; kills the empty-library risk for Brainforge itself).
- **(B) OSS-shaped Claude plugin: underway, and this repo is the result.** *Package* it
  cleanly from day one (`plugin.json`, commands/skills/templates separated from any one org's
  specific content). That separation forces finding the seam between "reusable pattern" and
  "one brain's specific canon", and that seam *is* the product. What you're reading is the
  output of that packaging step: a publishable set assembled from the private working repo by
  an allowlist-and-audit pipeline, not hand-curated from memory.
- **(C) commercial product**: still deferred. Hosting, auth, billing, multi-tenant are a
  different company; the honest path to C runs through a battle-tested B anyway.

## 7. Builder UX: `/forge`

**Depth-first, one loop at a time** (this is the roadmap philosophy turned into UX).

1. Ask which domains the team actually has (à la carte).
2. Pick one domain: default to the most *derivable* fast-win (eng or design: point at a repo
   or Figma file, watch real facts populate `derived/` in minutes). **Not brand**: too slow to
   feel valuable, blank-page tax up front.
3. Complete its full loop: scaffold → ingest → draft canon → approve → wire its one adapter →
   first sync → *read it back and feel the value*.
4. Only then offer the next domain.

Each domain loop is a natural save point. The wizard is **resumable by design**. Lead with a
win, defer the work (brand comes once the user is bought in).

## 8. Manager / day-2 layer

**Proactive surfacing built on the session-start hook** (the same hook that auto-pulls the
brain). Not passive tools you have to remember to run.

- **Flagship behavior: drift becomes a draft prompt.** When derived reality diverges from
  canon (e.g. site copy drifted from `brand/messaging.md`), Brainforge surfaces it *and hands
  the user a draft fix to approve*: same ingest→draft→approve loop, same PR gate, just
  *initiated by Brainforge instead of remembered by the user.* This closes the loop: derived
  facts provoke canon maintenance. It's the differentiating feature, and it's latent in what
  the original production brain already built.
- Also surfaces staleness (`last-reviewed` age) and broken syncs as one-line nudges.
- **Autonomous scheduled sync = opt-in per high-churn source, not default**: running agents +
  parked credentials + scheduled compute tip toward the deferred C-tier.

---

## Open / deferred (not decided here)

- **Naming:** shipping name is **Brainforge**. ("Cerebro" was the codename: Marvel IP, dropped.)
- **Extraction:** separating the reusable Brainforge spine from the source brain's
  org-specific canon and sources was the immediate next step at the time this decision record
  was written, and it defined the product seam. That work is done. This repo is the reusable
  spine it produced.
- **MCP universal reader, access tiers, autonomous scheduling, declarative adapters**: all
  parked, all additive.

---

## Amendments: 2026-08-08 (consumer layer design session)

Decided while designing subscribe + routing. The founding sections above stand; these extend
them.

### 9. The Consumer is a first-class role

§2 declared "every LLM is a reader" and then treated reading as a free capability of plain files.
It isn't. The reader has a contract of its own, parallel to the builder (§7) and manager (§8):

- **Presence**: the brain is on disk (or reachable) from the session that needs it.
- **Invocation**: the model consults the brain without a human remembering to ask.
- **Selection**: the model opens the *relevant slice*, scaled to what the slice costs.
- **Freshness**: already solved by §5/§8; the consumer layer only surfaces it (`last-synced`,
  commit age), never re-implements it.

Consequences: `.brainforge/brain-manifest.json` is a **core brain artifact** alongside
`sources.json` (regenerated deterministically on every sync, not only on demand), and the
index contract (`_index.md`) becomes **universal across canon and derived**: previously only
adapters emitted indexes, leaving the human-authored half of the brain unindexed.

### 10. Kinds: the catalog, one level down

Routing needs a machine-readable vocabulary for what a domain *is*. That vocabulary is not a
second taxonomy. It is the §4 catalog zoomed in one level. Each catalog preset defines the
`kinds` it emits, and `/forge` stamps them at scaffold time:

| Domain | Kinds emitted |
|---|---|
| `brand/` | `brand-voice`, `brand-messaging`, `naming`, `positioning`, `user-archetypes` |
| `product/` | `product-principles`, `product-roadmap`, `project-tracking`, `pricing-model` |
| `design/` | `design-principles`, `design-system`, `art-direction`, `ui-build-standards` |
| `eng/` | `repo-summaries`, `architecture-decisions`, `eng-conventions` |
| `analytics/` | `analytics`, `metric-definitions` |

A domain declares `kinds:` (a list: one folder may hold several) in its `_index.md` frontmatter.
Non-catalog brains (differently structured, hand-grown) route correctly by declaring kinds from
this same vocabulary; they never author routing rules. Growing the vocabulary is a Brainforge
change, not a per-brain one.

### 11. Sixth golden rule: extraction produces reference, not mirrors

The five golden rules govern how a sync runs; nothing governed what it may produce. Measured
consequence: one synced task-board doc grew to ~30k tokens (48% of an entire brain), a record
mirror, not reference. The rule: **a derived doc is what an LLM reasons *from* (inventories,
definitions, aggregates), never a replica of the source's records.** Mechanically:
adapters declare an expected size envelope in `ADAPTER-TEMPLATE.md`, and a sync PR that exceeds
it (or grows a doc dramatically) says so in the PR body. Cheap, deterministic, rides the existing
trust gate.

### 12. Three layers of behavior, not two

§1's two-layer form factor (brain vendors its runtime) gains a third layer for consumption:

| Layer | Lives in | Updates via | Why |
|---|---|---|---|
| Data (context + manifest) | the brain repo | sync PRs | the artifact itself |
| Maintenance behavior | vendored in the brain (`bump` paths) | `/upgrade` PR | the owner's toolchain must be self-sufficient |
| Consumption behavior | the **synapse** plugin, shipped by Brainforge | ordinary plugin update | routing improvements must reach every reader with zero brain-owner action |

Corollary: the intent table (intent → kinds) ships **in synapse only**: never vendored into
brains, or routing forks per brain and rots, the §1 disease.

### 13. Topology consequence (extends §3)

Subscribing the org means the whole org reads the whole brain. Access tiers stay deferred, but
the domain folder seams of §3 are now explicitly the future split points, and the sixth rule
(§11) is the interim control on what lands in front of every reader.

### 14. Rename: `/walk` → `/forge`

The flagship guided build is `/forge` (builder-side `/brainforge:forge` bootstraps; the
brain-resident `/forge` drives the loop). Same two-stage pattern, renamed only. `/upgrade`
learns to remove superseded command files it re-emits under a new name, so existing brains
don't keep both. All other command names stand. The shared consumer plugin (§12) is named
**synapse**.
