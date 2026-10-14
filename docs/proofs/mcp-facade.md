# MCP façade: live proof

Proven 2026-10-13 against a git copy of the synthetic `evals/fixtures/acme-brain`, run from an
empty directory, with `SYNAPSE_BRAINS` set only in each client's MCP server config
([spec](../specs/2026-10-13-mcp-facade.md)). The prompt was the same in every run up to 6:
"Write a two-sentence welcome message for new customers of our product, in our brand voice."

## What was run

| # | Client | Synapse plugin | Result |
|---|---|---|---|
| 1 | Codex CLI 0.162.1, `codex exec --json` | none (Codex has no synapse code) | No tool call. Codex asked what the product does. |
| 2 | Codex, prompt naming "the brain MCP tools" | none | `brain_map` **failed**: "MCP tool call requires approval, but approval policy is never" |
| 3 | Codex, same prompt, after the tools declared `readOnlyHint` | none | Grounded, cited, announced (below) |
| 4 | Codex, the original prompt, after the trigger fix and annotations | none | No tool call. Same as run 1. |
| 5 | Claude Code 2.1.296, `claude -p --strict-mcp-config`, the two tools in `--allowedTools` (headless mode cannot ask) | disabled with `--settings`; the init event lists no synapse plugin and no brain skill | Grounded, cited, announced, unprompted (below) |
| 6 | Codex, the original prompt, with the template's two-line rule in `AGENTS.md` | none | Grounded: `brain_map`, then the brand index and `voice.md`; announce line `🧠 loaded: Brand (voice.md)` |
| 7 | Codex, 2026-10-13 later: the same rule only in the global `~/.codex/AGENTS.md` (a temporary one, via `CODEX_HOME`), the project folder empty. Prompt: "Write the tagline for our homepage hero, in our brand voice." A control run without the rule came first | none | Control: no brain call; Codex searched the empty folder and asked for the brand. With the global rule: `brain_map`, then six `brain_read`s; announce line `🧠 loaded: Brand, Audience, Web · skipped: none` |

Run 3, the Codex event stream (`mcp_tool_call` items, all `completed`):

```
brain_map {}
brain_read {"brain": "acme-brain", "path": "context/canon/brand/_index.md"}
brain_read {"brain": "acme-brain", "path": "context/canon/audience/_index.md"}
brain_read {"brain": "acme-brain", "path": "context/canon/brand/voice.md"}
brain_read {"brain": "acme-brain", "path": "context/canon/audience/archetypes.md"}

Welcome to ACME. We're here to help you keep your team's infrastructure running calmly.
Based on `brand/voice.md` and `audience/archetypes.md`.
🧠 loaded: Brand, Audience · skipped: unrelated domains
```

Run 5, the Claude Code stream (`tool_use` blocks; no `Skill` call anywhere, $0.28):

```
mcp__brain__brain_map {}
mcp__brain__brain_read context/canon/brand/_index.md
mcp__brain__brain_read context/canon/audience/_index.md
mcp__brain__brain_read context/derived/mystery/_index.md
mcp__brain__brain_read context/canon/brand/voice.md
mcp__brain__brain_read context/canon/brand/naming.md
mcp__brain__brain_read context/canon/audience/archetypes.md

Welcome to ACME. Open Wrench to set up your workspace the way your team works.
…
🧠 loaded: Brand, Audience · skipped: Mystery (empty), Design, Design system, Pricing, Analytics, Tracker, Web, Repos, Company, Orion (unit)
```

Both clients followed the ladder the skill sets out: map, then indexes, then only the files an
index row named. Claude Code also peeked the unclassified `mystery` domain, which the skill tells
a reader to do for a domain with no kinds, and said so in the announce line.

## What the live run taught the server

- **Read-only has to be declared.** Run 2 failed because Codex refuses an MCP call that needs
  approval when it has no one to ask. Both tools now carry `annotations` with
  `readOnlyHint: true`, and the offline test asserts it.
- **The skill's trigger has to travel with the tools.** The plan stripped the skill's
  frontmatter, and with it the `description` that tells Claude Code *when* to load the skill. An
  MCP client sees only tool descriptions, so `brain_map`'s description now carries that sentence,
  read from the same `SKILL.md`.
- **Codex still needs to be told.** Even with the trigger in the description, Codex answered a
  brand-voice prompt by asking for the brand voice (run 4). Claude Code reached for the brain
  unprompted (run 5). The client template therefore ships a two-line project rule for clients
  that do not pick up MCP tools on their own. Run 6 is that rule, proven: the same prompt, now
  grounded. Run 7 puts it in Codex's global `~/.codex/AGENTS.md` instead, once for every project.
