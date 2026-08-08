# {{ORG}} — Shared Context

This repository is **{{ORG}}'s source of truth for brand, product, and design context**,
optimized to be read by humans *and* by LLMs (Claude Code, Cowork, ChatGPT, Cursor, etc.).

It is a **read-only reference**. You consume from it; you don't work inside it.
Your actual creative work — brainstorming, drafts, generated artifacts — lives in your
own workspace folder and *references* this repo. See [Consuming this repo](#consuming-this-repo).

> 🧠 Scaffolded by [Brainforge](https://github.com/jrpease/brainforge). The sync behavior in
> `pipeline/` and `.claude/commands/` is the versioned Brainforge runtime; everything in
> `context/` is yours.

---

## The one rule that makes this work: Canon vs. Derived

There are two kinds of content here, and they are treated completely differently.

| | `context/canon/` ✍️ | `context/derived/` 🤖 |
|---|---|---|
| **What** | Human-authored truth: voice, positioning, naming, principles | Machine-extracted facts: design tokens, component inventory, SKUs, site map |
| **Source of truth** | These files *are* the truth | A *downstream mirror* of Figma / repos / the live site |
| **Who writes it** | A human, carefully, via reviewed PR | The sync pipeline, automatically |
| **Trust** | Authoritative | Trust the upstream source; verify if unsure |
| **Editing** | Edit by hand (with review) | **Never hand-edit** — a sync will overwrite it |
| **Changes** | Rarely (weeks/months) | Often (whenever upstream work ships) |

If you remember nothing else: **canon is authored, derived is generated.** An LLM reading
this repo should treat canon as fact and derived as a faithful-but-regenerable snapshot.

---

## How context flows

```
SOURCES (where work happens)        THIS REPO                    CONSUMERS
─────────────────────────────       ──────────────────           ──────────────
Figma  ─┐                           context/derived/  ◀── sync   your LLM reads
repos  ─┼── sync (pipeline) ──▶     context/canon/    ◀── you     from here
site   ─┘                                                         (read-only)
```

- **Sources feed UP** into `derived/` via the pipeline (one direction).
- **Canon is authored here** directly.
- **Consumers read DOWN** from this repo — they never write back to it.
- Other repos/workspaces **reference** this repo's canon; they never copy it in
  (see [`templates/`](templates/)). Duplication is how a source of truth dies.

---

## Consuming this repo

Pick the path that matches the tool you use:

- **Claude Code / Cursor / any file-aware LLM** → clone it locally. It auto-pulls on session
  start (see `.claude/settings.json`), so your copy stays fresh without you remembering to
  `git pull`. Native file search/read is faster, cheaper, and works offline.
- **ChatGPT / browser / non-technical** → read it on GitHub directly (always current).

**Do your actual work elsewhere.** Open *your* workspace folder, point your LLM at this repo
as read-only reference, and write all outputs into your workspace. This repo stays pristine.

---

## Freshness — how to know if you're looking at stale truth

- Every **derived** doc carries a `last-synced` timestamp in its frontmatter.
- Every **canon** doc carries `owner` and `last-reviewed`.
- If a timestamp looks old, that's a signal — pull latest, or flag it (see
  [CONTRIBUTING.md](CONTRIBUTING.md)). Staleness should be *visible*, never silent.
- Sync health is checked by `/sync-health` (see `.claude/commands/`).

---

## Found something wrong or outdated?

You have read-only access — that protects integrity, but it means you can't fix it directly.
**Suggest the change** instead: see [CONTRIBUTING.md](CONTRIBUTING.md). Read-only consumption,
open suggestion.

---

## Scope — what belongs here, and what does NOT

**In scope:** brand identity & voice, positioning & messaging, naming conventions, product
principles & roadmap, design principles, design tokens, component inventory, SKU/dieline
reference, web/site inventory, repo summaries.

**Explicitly out of scope (non-goals):**
- ❌ A digital asset manager for raw photography / video / hi-res masters (those stay in Figma / a DAM / drive)
- ❌ A project tracker or task manager
- ❌ Analytics or dashboards
- ❌ A general file dump

A tight, trusted scope beats a sprawling junk drawer. If it isn't reference context someone's
LLM should reason from, it doesn't go here.

---

## Map of this repo

```
README.md            ← you are here
CLAUDE.md            ← instructions for any LLM that opens this repo
CONTRIBUTING.md      ← how to suggest changes (for read-only consumers)
sources.json         ← registry of watched sources (Figma files, repos, site)
.sync-state.json     ← pipeline memory: last-seen fingerprint per source (enables incremental sync)

context/
  canon/             ← ✍️  human-authored truth
  derived/           ← 🤖 machine-extracted, regenerable

pipeline/            ← ⚙️  the sync runtime (not consumed by readers)
  README.md          ← the six golden rules
  adapters/          ← one playbook per source type (figma, github, website, …)
  examples/          ← worked extension examples (e.g. shopify)
  ADAPTER-TEMPLATE.md← the skeleton every adapter fills
authoring/           ← ✍️  the canon builder method (counterpart to pipeline/)
  README.md          ← ingest→interview→draft→approve + the guardrail rules
  templates/         ← per-domain starter canon skeletons
setup/               ← 🧭 the guided walk (fill one domain end-to-end, then offer the next)
  README.md          ← guard → status ladder → fast-win routing → inline loop → read it back
templates/           ← reference-don't-duplicate snippets (see `brain-pointer-snippet.md`)
.claude/
  commands/          ← /forge, /sync, /add-source, /add-adapter, /drift, /sync-health, /draft-canon, /approve-canon
  settings.json      ← auto-pull-on-session-start hook (keeps clones fresh)
```
