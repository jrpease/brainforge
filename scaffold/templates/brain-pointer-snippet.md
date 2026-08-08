# Snippet: point any file-aware LLM tool at this brain (Cursor, Codex, Copilot, …)

Claude Code users get routing via the synapse plugin. Every other file-aware tool gets this
block instead — paste it into the product repo's `AGENTS.md` (Codex), `.cursor/rules` (Cursor),
or equivalent. Replace `<brain-path>` with the clone location (e.g. `~/.synapse/{{ORG}}-brain`
or a sibling checkout). Same brain, same manifest — less enforcement: pull the brain
periodically yourself, this tool won't do it for you.

```markdown
## {{ORG}} brain — source of truth (read-only)

The org's brain lives at <brain-path>. Before answering anything that touches brand voice,
copy, naming, design, product principles, metrics, or org facts:

1. Read `<brain-path>/.brainforge/brain-manifest.json` — it lists every domain with its
   `kinds`, token cost, and a `band`.
2. Open only relevant domains, gated by band: `cheap` → open freely when plausibly relevant;
   `normal` → open on a direct topical match; `expensive` → never whole-domain — read the
   domain's `_index.md` and open only the specific files needed.
3. `context/canon/` is human-authored truth. `context/derived/` is machine-synced — check its
   `last-synced` frontmatter and say so if it looks old. If they contradict, report the
   conflict; don't pick one.
4. End grounded responses with one line: `brain loaded: <domains> · skipped: <domains>`.
5. Never edit the brain. Write outputs in this repo/workspace only. If the brain looks wrong,
   suggest a change via its CONTRIBUTING.md.
```
