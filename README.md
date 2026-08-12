# Brainforge

> A living brain for your product org: what your team wrote by hand, plus facts pulled straight
> from your real tools, so it never goes stale.

Your single source of truth goes stale the day after you write it. Someone renames a component,
ships a new route, changes how a metric is defined, and the doc that was supposed to be
canonical is quietly wrong. Every AI tool you point at it inherits the rot.

Brainforge builds a brain for your product org and keeps it current for you. Half of it is what
a human wrote and stands behind: voice, positioning, principles. The other half is pulled
straight from the tools you already use (Figma, GitHub, GA), so the facts match reality without
anyone maintaining them by hand. It's one git repo of plain markdown and JSON. Any LLM can read
it: Claude, Cursor, whatever comes next.

---

## What you get

- **Truth that stays true.** The auto-synced half (tokens, components, routes, metrics) pulls
  straight from its source. When the source changes, the brain changes. No stale doc, no manual
  reconciliation.
- **Authored knowledge that stays authoritative.** Brand voice, principles, and conventions are
  written by a human and protected: an automatic sync can never overwrite them.
- **Every change reviewed before it lands.** Nothing edits your brain silently. A sync proposes a
  branch; a human merges it. You see the diff first, every time.

---

## How it works, at a glance

Every brain splits its content two ways, and treats each half completely differently: what a
**human wrote** and stands behind, and what a **pipeline keeps current** from a live source.
Brainforge calls these two halves **Canon** and **Derived**.

| | **Canon** ✍️ | **Derived** 🤖 |
|---|---|---|
| **What** | Human-authored truth: voice, positioning, principles, conventions | Machine-extracted facts: tokens, components, routes, metrics |
| **Source of truth** | These files *are* the truth | A regenerable mirror of an upstream source |
| **Who writes it** | A human, via reviewed PR | The sync pipeline, automatically |
| **Editing** | By hand, with review | Never by hand: a sync overwrites it |

Domains sit on a spectrum from **authored** (brand) to **derived** (eng, analytics). You start
where the value lands fastest, usually eng or design, and add the rest as you feel the payoff.

---

## Get started

Install it as a Claude Code plugin:

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

Then make a home for your brain and start the forge:

```
mkdir my-brain && cd my-brain && git init
```

In a Claude Code session inside that folder, run `/brainforge:forge`. The first run bootstraps the
brain: it lays down the starting files (the scaffold), commits them, and hands off to the brain's
own `/forge` command. Restart the session so the new commands load, then run `/forge` again.

From there it's a guided setup. It picks one domain to start with (the fastest, most derivable
win) and drives the whole loop for you: create the folders, pull real material into a draft,
pause for your approval, wire up an adapter (the small playbook that pulls from one tool), run
the first sync, then read the result back so you watch real facts land in `derived/` before it
offers you the next domain. It never tracks progress in a separate state file: it recomputes
where you are from the brain's actual contents every time, so it can't drift from reality.

---

## Reading a brain (your whole team)

Building a brain is one person's job. Reading it is everyone's. Teammates don't install the
brain, they subscribe to it:

- **Claude Code** → install the **synapse** plugin (`claude plugin install synapse@brainforge`),
  then run `/synapse:subscribe <brain-git-url>` once, or just open a product repo that already
  commits the subscription settings (see `synapse/templates/product-repo-settings.md`). Every
  session auto-pulls the brain, shows a roughly 300-token map, and routes prompts to only the
  slice they need, announcing what it loaded and skipped.
- **Cursor / Codex / any file-aware tool** → paste the pointer block
  (`scaffold/templates/brain-pointer-snippet.md`) into the repo's rules file. Same manifest (a
  machine-readable summary of the brain's shape), same reading rules.
- **Web-only tools (ChatGPT, Claude.ai)** → on the roadmap: a read-only MCP endpoint over the
  same manifest.

---

## What it connects to

Each source below is one of two kinds: an **entity-snapshot** (a list of things, like components
or tickets) or a **metrics / time-series** source (numbers over time, like traffic).

| Adapter | Kind | Proven live |
|---|---|---|
| [GitHub](scaffold/pipeline/adapters/github.md) | entity-snapshot | [proof](docs/proofs/github-adapter.md) |
| [Figma](scaffold/pipeline/adapters/figma.md) | entity-snapshot | [proof](docs/proofs/figma-adapter.md) |
| [Monday](scaffold/pipeline/adapters/monday.md) | entity-snapshot | [proof](docs/proofs/monday-adapter.md) |
| [GA](scaffold/pipeline/adapters/ga.md) | metrics / time-series | [proof](docs/proofs/2026-07-02-ga-live/README.md) |
| [Website](scaffold/pipeline/adapters/website.md) | entity-snapshot | built-in, no live proof session yet |
| [Shopify](scaffold/pipeline/examples/shopify.md) | entity-snapshot | worked `/add-adapter` example, see the [walkthrough](docs/walkthroughs/shopify-add-adapter.md) |

Need a source we don't ship a built-in for? That's a command, not a code change. Run
`/add-adapter` and fill in `scaffold/pipeline/ADAPTER-TEMPLATE.md`, the same skeleton every
built-in fills. The Shopify adapter above was built exactly this way; the
[worked walkthrough](docs/walkthroughs/shopify-add-adapter.md) shows the full path, and
[CONTRIBUTING.md](CONTRIBUTING.md) covers sending a new adapter back upstream.

---

## Under the hood

### The six golden rules

Every sync playbook in `scaffold/pipeline/` follows the same six rules ([full detail](scaffold/pipeline/README.md)):

1. **Work scales with the delta (only what changed), not the whole corpus.** Run a cheap check
   first, a fingerprint (a lightweight marker of whether the source moved at all), and do the
   expensive extraction only on what changed.
2. **REST API, not MCP.** Sync uses cheap REST endpoints; interactive MCPs are reserved for a
   human actually designing.
3. **Deterministic extraction over LLM summarization.** Prefer tooling that produces the same
   output every run; reserve an LLM pass for genuinely narrative output, gated hardest.
4. **Every sync lands via PR, never a direct write.** A sync proposes a branch; a human merges.
5. **Always update provenance and state.** Every derived file carries a note on where it came
   from and when (`source`/`last-synced`), and `.sync-state.json` records the fingerprint at the
   end of a successful sync.
6. **Extraction produces reference, not mirrors.** Derived docs are reference material an LLM
   reasons from, not full replicas of the source; a sync that lands a doc over its expected size
   envelope must say so in the PR.

### How upgrades work

A brain isn't scaffolded once and abandoned: the sync playbooks and commands are a versioned,
re-emittable runtime (the parts of a brain that Brainforge keeps updated for you), not a
one-time copy. `plugin.json` declares which shipped paths are that runtime (`bump`, re-emitted on
upgrade) versus which are emitted once at birth and owned by the brain forever (`once`). A
`.brainforge/runtime-manifest.json`, written at scaffold time, hashes every bump file so
`/upgrade` can tell clean files (safe to overwrite) from ones you've edited (flagged, never
clobbered) from ones you've added yourself (never touched). An upgrade always lands as a PR on
the brain, never a direct write, so a human reviews the diff before it merges.

---

## Design & roadmap

See [DESIGN.md](DESIGN.md) for the full design rationale and [ROADMAP.md](ROADMAP.md) for what's
shipped and what's next.

## License

MIT, see [LICENSE](LICENSE).
