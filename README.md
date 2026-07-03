# Brainforge

> The Claude-native way to **build and operate a "product-org brain"** — a tool-agnostic
> git repo of *authored truth* + *synced facts* that any LLM can read.

Brainforge walks a team through standing up an AI brain for their product organization — brand,
product, design, eng, analytics — one domain at a time, then keeps that brain alive as the
underlying sources change. It's extracted from a pattern running in production at a design org:
one repo any LLM can open, split cleanly into what a human wrote and what a pipeline verified.

---

## The core idea: Canon vs. Derived

Every brain Brainforge produces splits content two ways, and treats them completely differently:

| | **Canon** ✍️ | **Derived** 🤖 |
|---|---|---|
| **What** | Human-authored truth: voice, positioning, principles, conventions | Machine-extracted facts: tokens, components, routes, metrics |
| **Source of truth** | These files *are* the truth | A regenerable mirror of an upstream source |
| **Who writes it** | A human, via reviewed PR | The sync pipeline, automatically |
| **Editing** | By hand, with review | Never by hand — a sync overwrites it |

Domains sit on a spectrum from **authored** (brand) to **derived** (eng, analytics).

---

## The five golden rules

Every sync playbook in `scaffold/pipeline/` follows the same five rules ([full detail](scaffold/pipeline/README.md)):

1. **Work scales with the delta, not the corpus** — run a cheap change-detection gate first; do
   expensive extraction only on what changed.
2. **REST API, not MCP** — sync uses cheap REST endpoints; interactive MCPs are reserved for a
   human actually designing.
3. **Deterministic extraction over LLM summarization** — prefer tooling that produces the same
   output every run; reserve an LLM pass for genuinely narrative output, gated hardest.
4. **Every sync lands via PR, never a direct write** — a sync proposes a branch; a human merges.
5. **Always update provenance + state** — every derived file carries `source`/`last-synced`, and
   `.sync-state.json` records the fingerprint at the end of a successful sync.

---

## Install

As a Claude Code plugin:

```
claude plugin marketplace add jrpease/brainforge
claude plugin install brainforge@brainforge
```

For development, clone the repo and add it as a local marketplace instead:

```
git clone https://github.com/jrpease/brainforge.git
claude plugin marketplace add ./brainforge
claude plugin install brainforge@brainforge
```

---

## Quickstart

```
mkdir my-brain && cd my-brain && git init
```

Then, in a Claude Code session inside that directory, run `/walk`. The first run bootstraps the
brain — it emits the scaffold, writes the birth manifest, commits, then hands off to the brain's
own `/walk` (restart the session so the new project commands load, then run `/walk` again). That
one is the depth-first setup wizard: it offers one domain to start with, recommending the fastest,
most derivable win — eng or design — and deferring brand until you've felt the value. For that
domain it drives one seamless loop: scaffold the folders and templates, ingest real material into
a draft, gate the draft at approval, wire a built-in adapter (or add a new one), run the first
sync, then read the result back so you see real facts land in `derived/` before it offers you the
next domain. Progress is never stored in a state file — it's recomputed from the brain's actual
contents every time, so it can't drift from reality.

---

## Adapter roster

| Adapter | Kind | Proven live |
|---|---|---|
| [GitHub](scaffold/pipeline/adapters/github.md) | entity-snapshot | [proof](docs/proofs/github-adapter.md) |
| [Figma](scaffold/pipeline/adapters/figma.md) | entity-snapshot | [proof](docs/proofs/figma-adapter.md) |
| [Monday](scaffold/pipeline/adapters/monday.md) | entity-snapshot | [proof](docs/proofs/monday-adapter.md) |
| [GA](scaffold/pipeline/adapters/ga.md) | metrics / time-series | [proof](docs/proofs/2026-07-02-ga-live/README.md) |
| [Website](scaffold/pipeline/adapters/website.md) | entity-snapshot | built-in, no live proof session yet |
| [Shopify](scaffold/pipeline/examples/shopify.md) | entity-snapshot | worked `/add-adapter` example — see the [walkthrough](docs/walkthroughs/shopify-add-adapter.md) |

---

## Extending

Adding a source Brainforge doesn't ship a built-in for is a Claude Code command, not a code
change: run `/add-adapter` and fill in `scaffold/pipeline/ADAPTER-TEMPLATE.md` — the same skeleton
every built-in adapter fills. The Shopify adapter above was built exactly this way; see the
[worked walkthrough](docs/walkthroughs/shopify-add-adapter.md) for the full extension path, and
[CONTRIBUTING.md](CONTRIBUTING.md) for how to send a new adapter back upstream.

---

## How upgrades work

A brain isn't scaffolded once and abandoned — the sync playbooks and commands are a versioned,
re-emittable runtime, not a one-time copy. `plugin.json` declares which shipped paths are that
runtime (`bump`, re-emitted on upgrade) versus which are emitted once at birth and owned by the
brain forever (`once`). A `.brainforge/runtime-manifest.json`, written at scaffold time, hashes
every bump file so `/upgrade` can tell clean files (safe to overwrite) from ones you've edited
(flagged, never clobbered) from ones you've added yourself (never touched). An upgrade always
lands as a PR on the brain, never a direct write, so a human reviews the diff before it merges.

---

## Design & roadmap

See [DESIGN.md](DESIGN.md) for the full design rationale and [ROADMAP.md](ROADMAP.md) for what's
shipped and what's next.

## License

MIT — see [LICENSE](LICENSE).
