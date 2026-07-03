# Brainforge — locked design

This is the decision record from the founding design session. Each section is a resolved
branch of the design tree, with the reasoning preserved so future contributors understand
*why*, not just *what*.

**One line:** *The Claude-native way to build and operate a "product-org brain" — a
tool-agnostic git repo of authored truth + synced facts that any LLM can read.*

The whole design is a generalization of a pattern already proven in production. This pattern
was extracted from a production brain built for SWEET, a design org; that live testbed is why
none of this is speculative. The guiding constraint, inherited from that work: **prove one
loop end-to-end before scaling — the #1 failure mode is a beautiful empty library nobody
filled.**

---

## 1. Form factor

**Generator that scaffolds a self-sufficient brain repo and vendors a thin, re-emittable
runtime.** Tooling upgrades (sync playbooks, commands) come down as regenerated files via PR.

- *Not* a pure generator (every brain would fork the logic at birth and rot — bug fixes never
  reach already-generated brains; that's duplication, which the architecture exists to kill).
- *Not* a pure runtime (would couple every consumer to Brainforge being installed/alive,
  betraying the "materialized files, not a live proxy" principle).
- The brain stays a self-sufficient git repo (zero external dependency); the *behavior* is
  versioned and upgradable. Like `create-react-app` scaffolding + bumpable `react-scripts`.

## 2. Cross-LLM strategy

**The brain artifact is tool-agnostic** (markdown + JSON in git, readable by any file-aware
LLM). **The builder + manager layer is Claude-first.**

- The brain being plain files *is* the cross-LLM strategy — it already works everywhere.
- The guided setup experience is where Claude shines and is hard to replicate elsewhere, so:
  **Claude is the author's tool; every LLM is a reader.**
- Rejected: per-platform builders (Cursor rules + GPT config + …) — four scaffolds that drift
  out of sync, the exact disease this cures.
- **MCP** parked as the eventual *universal reader* (the no-git path for ChatGPT /
  non-technical teammates). Strictly additive; does not gate v1.

## 3. Topology

**One product-org brain, multiple domains** — not many brains.

- The functions in scope all orbit the *same* artifacts (the product, design system, codebase,
  metrics), so they belong in one brain, not disconnected ones.
- Domains are an **à la carte menu, not a mandate** — set up only what the team has. An R&D
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

- Structure isn't the value; canon is — and Brainforge cannot *know* a company's voice.
- Turn blank-page paralysis into editing (10x easier). Bootstrap the first draft from real
  material (deck, site, PRDs, READMEs), interview only for gaps.
- **Hard guardrail:** Brainforge-drafted canon must be *loudly provisional*. A confidently
  wrong auto-draft that a human rubber-stamps is worse than an empty stub — it launders
  fabrication into "truth" that then propagates to every LLM. Brand is the dangerous domain
  (subjective, low source material); the derived-leaning domains are safer to bootstrap.

## 5. Sync adapters

**Prose-but-contractual.** An adapter = a markdown playbook filling a fixed skeleton +
a `sources.json` schema entry + a generated slash command.

- The five golden rules *are* the contract, inherited from that original production pipeline:
  1. **Work scales with the delta, not the corpus** — cheap change-detection gate first,
     expensive extraction only on what changed.
  2. **REST, not MCP** for sync — MCP is heavy/token-hungry, reserved for interactive work.
  3. **Deterministic extraction over LLM summarization** wherever possible.
  4. **Every sync lands via PR, never a direct write** — the human trust gate.
  5. **Always update provenance + state** — `source` / `last-synced` / `generated-by`
     frontmatter + the sync-state fingerprint.
- Ship `pipeline/ADAPTER-TEMPLATE.md` (the canonical skeleton: gate / extract / emit /
  provenance / command) + an `/add-adapter` scaffolder. Consumers extend by filling the
  skeleton, not reverse-engineering style.
- *Not yet*: a declarative spec language or executable plugins — premature; prove the path in
  prose first.
- **Built-in adapters:** Figma, GitHub, Jira, Monday, GA.
- **Shopify = the documented extension example** — already built to solve a real e-commerce
  integration need, then re-added via `/add-adapter` to prove the extension path is real, not
  aspirational.

## 6. Distribution & intent

**Build for A, package as B, defer C.**

- **(A) internal tooling — done.** Built by extracting from the same production brain built
  for SWEET (a real, live testbed; kills the empty-library risk for Brainforge itself).
- **(B) OSS-shaped Claude plugin — underway, and this repo is the result.** *Package* it
  cleanly from day one (`plugin.json`, commands/skills/templates separated from any one org's
  specific content). That separation forces finding the seam between "reusable pattern" and
  "one brain's specific canon" — and that seam *is* the product. What you're reading is the
  output of that packaging step: a publishable set assembled from the private working repo by
  an allowlist-and-audit pipeline, not hand-curated from memory.
- **(C) commercial product** — still deferred. Hosting, auth, billing, multi-tenant are a
  different company; the honest path to C runs through a battle-tested B anyway.

## 7. Builder UX — the "walk"

**Depth-first, one loop at a time** (this is the roadmap philosophy turned into UX).

1. Ask which domains the team actually has (à la carte).
2. Pick one domain — default to the most *derivable* fast-win (eng or design: point at a repo
   or Figma file, watch real facts populate `derived/` in minutes). **Not brand** — too slow to
   feel valuable, blank-page tax up front.
3. Complete its full loop: scaffold → ingest → draft canon → approve → wire its one adapter →
   first sync → *read it back and feel the value*.
4. Only then offer the next domain.

Each domain loop is a natural save point — the wizard is **resumable by design**. Lead with a
win, defer the work (brand comes once the user is bought in).

## 8. Manager / day-2 layer

**Proactive surfacing built on the session-start hook** (the same hook that auto-pulls the
brain). Not passive tools you have to remember to run.

- **Flagship behavior: drift becomes a draft prompt.** When derived reality diverges from
  canon (e.g. site copy drifted from `brand/messaging.md`), Brainforge surfaces it *and hands
  the user a draft fix to approve* — same ingest→draft→approve loop, same PR gate, just
  *initiated by Brainforge instead of remembered by the user.* This closes the loop: derived
  facts provoke canon maintenance. It's the differentiating feature, and it's latent in what
  the original production brain already built.
- Also surfaces staleness (`last-reviewed` age) and broken syncs as one-line nudges.
- **Autonomous scheduled sync = opt-in per high-churn source, not default** — running agents +
  parked credentials + scheduled compute tip toward the deferred C-tier.

---

## Open / deferred (not decided here)

- **Naming:** shipping name is **Brainforge**. ("Cerebro" was the codename — Marvel IP, dropped.)
- **Extraction:** separating the reusable Brainforge spine from the source brain's
  org-specific canon and sources was the immediate next step at the time this decision record
  was written, and it defined the product seam. That work is done — this repo is the reusable
  spine it produced.
- **MCP universal reader, access tiers, autonomous scheduling, declarative adapters** — all
  parked, all additive.
