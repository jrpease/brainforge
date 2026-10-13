# MCP façade

Status: built
Reviewed: 2026-10-13 — ready to build (second pass; three minor tightenings applied)
Date: 2026-10-13

## Goal

Today a brain can be read only from Claude Code (the synapse plugin) or from a tool pointed at a
git checkout by hand (`brain-pointer-snippet.md`). After this ships, any local MCP client (Claude
Desktop, Cursor, Codex, VS Code, Windsurf, or anything else that speaks the Model Context
Protocol over stdio) on macOS or Linux can subscribe to the same brains and read them with the
same routing the plugin uses, by adding one server entry to its config. The reader stays one
implementation: the server runs the synapse hook for the map and serves the brain-routing skill
as its instructions, so a routing change still reaches every reader by a plain update.

## Non-goals

- **No hosted endpoint.** ChatGPT web and Claude.ai (roadmap tier 3) need a public HTTPS URL
  plus OAuth in front of a private brain. That is a hosting and access-control product, not a
  reader, and it is the first open question below. This spec ships the reader every such
  deployment would wrap; tier 3 stays open.
- **No writes.** The server never edits, commits or pushes a brain. Its only side effect is the
  same clone/pull the synapse hook already does under `$SYNAPSE_HOME`.
- **No server-side routing.** Picking which docs to open stays model judgement, governed by the
  skill text. The server does not match intents, score domains or enforce bands.
- **No search tool, no size caps, no access tiers.** None of them is in the reader today.
- **No change to the brain runtime.** Nothing under `scaffold/` changes, so no brain needs an
  `/upgrade`.
- **No native Windows.** The map is the bash hook; Windows works only under Git Bash or WSL.

## Decisions

Jordan delegated these on 2026-10-13 ("take your recommendations when you have a question; only
pull me in for an important P0 question"). Each row is Claude's call under that delegation, not a
choice Jordan made in conversation.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Transport | stdio only | Every desktop/IDE MCP client speaks it, it needs no port, no auth and no hosting, and it is the core any remote deployment would wrap | Reaching ChatGPT web / Claude.ai in this release |
| Language | One stdlib-only `python3` file, `synapse/mcp/server.py` | `python3` is already the one non-shell dependency (`/synapse:subscribe`); MCP's stdio framing is newline-delimited JSON-RPC, small enough to hand-roll; no `pip install` for a stranger | An SDK dependency (`mcp` on PyPI, Node) |
| Where the map comes from | `brain_map` runs `synapse/hooks/session-start.sh` and returns its stdout | One implementation of clone/pull, collision handling, staleness, coverage lines and every loud failure line; the façade cannot drift from the plugin | A second map renderer |
| Where the routing rules come from | The server's `instructions` are a preamble plus the body of `synapse/skills/brain-routing/SKILL.md`, read at startup | The skill is the routing, so serving it verbatim keeps one source | Paraphrased rules in the server |
| Clients that drop `instructions` | The three load-bearing rules also go in the tool descriptions: call `brain_map` first; read only through `brain_read` with the map's brain name; end grounded answers with the announce line | MCP makes `instructions` an optional hint and client support is uneven; tool descriptions are always shown | — |
| Routing table | `brain_map` appends `synapse/routing/intents.json` verbatim | The skill tells the model to read it from the plugin root, which an MCP client cannot see | — |
| Tools | Two: `brain_map` (no args) and `brain_read {brain, path}`. `brain_read` on a directory lists its subdirectories and its `.md`/`.json` files, nothing else | Matches the disclosure ladder (map → index → files) and the skill's "unindexed: read the files directly" case; listing only what can be read keeps the fence's shape | Per-domain or per-kind tools |
| Brain resolution | `brain` is a name the latest `brain_map` printed, in either the header `🧠 <name> — brain at <dir> (last change …` or the no-manifest line `🧠 synapse: <name> has no manifest — read <dir>/context/ directly …`. The server takes `<dir>` from that output. Any other name is refused | The hook owns directory choice (collision suffixes exist), and brains that predate manifests are a live case (ROADMAP's backfill note) | Reconstructing paths from names |
| Read fence | `path` is relative to the brain dir. Allowed: exactly `.brainforge/brain-manifest.json`, or anything that resolves (after symlinks) inside `<dir>/<contextRoot>` (manifest's `contextRoot`, else `context`). Files must be `.md` or `.json`, the two types `gen-manifest.sh` counts | The skill being served reads the manifest (`kinds`, `indexTokens`, per-file lists), and the manifest is the data the brain publishes. Everything else (`.git/`, workflows, `CLAUDE.md`, symlink targets) is outside the reference | Reading other `.brainforge/` files or anything outside the context root |
| A brain in the client's cwd | The preamble says the brains this server serves are the ones `brain_map` prints, read through `brain_read`; a brain open in the client's own workspace is the client's file access, not this server's | The skill's "Locate the brain" step 2 assumes Claude Code; a file-aware client should not mix the two silently | — |
| Configuration | The client sets `SYNAPSE_BRAINS` (and optionally `SYNAPSE_HOME`, `SYNAPSE_NET_TIMEOUT`) in the server's `env` block, the same variables the plugin uses. The template shows an absolute `python3` path | No new config surface; a Claude Code user's `~/.synapse` clones are shared. Desktop clients spawn servers with a sparse `PATH` | A server-specific config file |
| Pointer snippet vs façade | The README recommends the façade for any MCP client; the pointer snippet stays for tools without MCP | The façade brings the routing and loud failures, the snippet only a path | — |
| Version | synapse 0.7.5 → 0.8.0; brainforge unchanged | New capability in synapse only | — |

## Open questions

- **Hosted endpoint for ChatGPT web and Claude.ai (tier 3).** Options: (a) a documented
  self-host recipe (the org runs this server behind an HTTPS MCP gateway with its own OAuth), (b)
  a streamable-HTTP transport in this server plus a deploy template that reads the brain from
  GitHub with a token, (c) wait for demand. Recommendation: (c) until a subscribing team asks,
  then (b) as its own spec; the access-control decision (who may read which brain) is Jordan's.
  Unresolved.
- **Status-aware reads.** The skill never reads `status: draft`, and neither will the façade,
  since it serves the skill. Recommendation: fix it in the skill, where both readers get it, as a
  separate change with a routing eval. Unresolved.

## What shipped

- `synapse/mcp/server.py`: the stdio server, as Step 1, plus the two divergences below.
- `tests/synapse-mcp.test.sh`: as Step 2, plus a committed symlink out of the brain (refused), a
  `.txt` file left out of a listing, the read-only annotations and the trigger sentence. Mutation
  check run: opening the fence, answering notifications, dropping the map-first rule, dropping
  the no-manifest parse and listing every file each made the test fail; the last one survived
  until the `.txt` case was added. Full suite: 29 PASS.
- `docs/proofs/mcp-facade.md` and its row in `docs/proofs/README.md`: six live runs, Codex and
  Claude Code.
- `synapse/templates/mcp-client-config.md`; synapse 0.8.0; README and ROADMAP as Step 4.

## Where it diverged

- **Tools declare `annotations` with `readOnlyHint: true`.** Not in the plan. Live run 2 failed
  because Codex refuses an unannotated MCP call it cannot get approval for.
- **The skill's `description` is no longer dropped.** Step 1 stripped the frontmatter whole; that
  sentence is what tells a client *when* to use the brain. It now opens `brain_map`'s tool
  description and the instructions, read from the same `SKILL.md`.
- **Codex does not use the brain unprompted** even with the trigger sentence (live run 4), so the
  template gained a step 3: a two-line project rule, proven in run 6. Claude Code needed no rule.
- **Step 3's Claude Code command** also needed `--allowedTools` for the two tools, because
  headless mode cannot ask for permission, and disabled `brainforge@brainforge` too.
- **Diff review fixes** (critic, after the build): `brain_map` returns `isError` when the hook
  exits non-zero or prints no brain line (a hook killed by a sparse env had returned an empty map
  as success), with a 300s bound; `.git` is never read or listed, even under a `.` context root;
  a NUL path or non-object `arguments` is a tool error or `-32602`, not `-32603`; a closed
  stdout ends the server quietly; the two hook lines the server parses carry signpost comments.
  New tests: a `docs` context root read through the manifest value, a `.` root, a crashed hook.
  Ten mutations, each caught.
- **Also touched:** `DESIGN.md`'s two "MCP universal reader … parked" lines, narrowed to the
  hosted endpoint, and `synapse/hooks/session-start.sh` (comments only).

## Plan

### Step 1 — The server

Files: `synapse/mcp/server.py`
Change: stdlib-only, `#!/usr/bin/env python3`. `PLUGIN = Path(__file__).resolve().parent.parent`.
Read stdin line by line as UTF-8; each non-blank line is one JSON-RPC 2.0 message. Write one
compact JSON object per line to stdout, flush after each; logs go to stderr only.

- `initialize` → result `{protocolVersion, capabilities: {tools: {}}, serverInfo: {name:
  "synapse", version}, instructions}`. `protocolVersion` = the client's if it is one of
  `2024-11-05`, `2025-03-26`, `2025-06-18`, `2025-11-25`, else `2025-11-25`. `version` is read
  from `PLUGIN/.claude-plugin/plugin.json`. `instructions` = preamble + SKILL.md with its leading
  `---` frontmatter block removed. The preamble says: call `brain_map` first, once per
  conversation; the map is the manifest's rendering, and the routing table the skill mentions
  (`${CLAUDE_PLUGIN_ROOT}/routing/intents.json`) is printed at the end of `brain_map`; every file
  the skill says to read (the manifest, an `_index.md`, a content file) is
  `brain_read(brain, path)` with the brain name from the map and a path relative to that brain,
  e.g. `context/canon/brand/_index.md` or `.brainforge/brain-manifest.json`; the brains this
  server serves are the ones `brain_map` prints, and a brain open in the client's own workspace
  is outside this server.
- A message with no `id` is a notification: no response. `ping` → result `{}`. `tools/list` →
  `{tools: [{name, description, inputSchema}]}`: `brain_map` with
  `{"type":"object","properties":{}}`; `brain_read` with required string properties `brain` and
  `path`. Both descriptions carry the three load-bearing rules (Decisions). Unknown method →
  error `{code: -32601}`. Unparseable line → error `{code: -32700}` with `id: null`.
- `tools/call` results are always `{content: [{type: "text", text}], isError?: true}`; tool
  failures set `isError: true` and never raise a JSON-RPC error. Unknown tool name → `isError`.
- `brain_map`: if `SYNAPSE_BRAINS` is unset or blank → `isError`, text "no brains configured: set
  SYNAPSE_BRAINS in this server's env". Otherwise run `bash PLUGIN/hooks/session-start.sh` with
  the inherited env, stdout captured and decoded as UTF-8. Replace the name → dir table with the
  names parsed from `^🧠 (\S+) — brain at (.+) \(last change` and
  `^🧠 synapse: (\S+) has no manifest — read (.+)/context/ directly`. Return the hook stdout +
  `\n\nRouting table (intents → kinds):\n` + intents.json text.
- `brain_read`: `isError` when no `brain_map` has run in this process ("call brain_map first"),
  the brain is not in the table, `path` is absolute or empty, or the resolved path is neither
  exactly `<dir>/.brainforge/brain-manifest.json` nor inside the resolved `<dir>/<contextRoot>`.
  `contextRoot` comes from the manifest line `  "contextRoot": "…",` when the manifest exists,
  else `context`. Directory → sorted entries, subdirectories with a `/` suffix and `.md`/`.json`
  files, one per line. File: must be `.md` or `.json`, else `isError`; returns its UTF-8 text. A
  missing path → `isError` "not found".

Verify: Step 2.

### Step 2 — Offline test

Files: `tests/synapse-mcp.test.sh`
Change: follow `tests/synapse-hook.test.sh`'s shape (`ROOT`, `mktemp` `TMP` with a cleanup
trap, `fail()`, `echo PASS`). Copy `evals/fixtures/acme-brain` into `$TMP/acme-brain`, `git init`,
`git add -A`, commit. Set `SYNAPSE_HOME=$TMP/home`, `SYNAPSE_BRAINS=$TMP/acme-brain`. A python3
helper sends a list of messages to one server process and returns its stdout lines parsed, keyed
by `id`. Every assertion addresses a response by its request `id`:

- Session A, in order: `initialize` (id 1), `notifications/initialized` (no id), `tools/list`
  (2), `brain_map` (3), reads of `context/canon/brand/_index.md` (4), `context/canon` (5),
  `.brainforge/brain-manifest.json` (6), `../outside.md` (7), an absolute path (8),
  `.git/config` (9), `context/canon/brand/../../../README.md` (10), an unknown brain (11), an
  unknown method (12), and a line of invalid JSON.
- Assert: output line count = 13 (twelve ids plus the parse error), which proves the
  notification got no reply and the server survived every request; id 1 `instructions` contains
  `Announce` and `brain_read`; id 2 tool names are exactly `brain_map, brain_read`; id 3 has no
  `isError` and contains `🧠 acme-brain — brain at` and `"writing user-facing copy"`; id 4 text
  equals the fixture file; id 5 lists `brand/`; id 6 contains `"contextFingerprint"`; ids 7–11
  each have `isError: true`; id 12 has error code `-32601`; the parse error has code `-32700` and
  `id` null.
- Session B (fresh process): `brain_read` before any `brain_map` → `isError` containing
  `brain_map first`.
- Session C: a brain whose `.brainforge/brain-manifest.json` is deleted. `brain_map` contains
  `has no manifest`, and reading `context/canon/brand/_index.md` through it succeeds.
- Session D: `SYNAPSE_BRAINS` empty → `brain_map` `isError` containing `no brains configured`.

Mutation check before committing: make the fence allow any path and confirm the test fails; then
revert. Record that it was run in What shipped.
Verify: `bash tests/synapse-mcp.test.sh` → `PASS`; then the CI loop
`for t in tests/*.test.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"; done`
prints 29 `PASS` lines (28 today plus this one) and no `FAIL`.

### Step 3 — Live check in real MCP clients

Change: `docs/proofs/mcp-facade.md` (new), plus its row in `docs/proofs/README.md`.
Run the server against a git copy of the acme fixture (as in Step 2), from an empty scratch
directory, with `SYNAPSE_BRAINS` set only in the client's MCP server config:

- **Codex** (no synapse code at all, so a pass can only come from the server):
  `codex exec --json --skip-git-repo-check -c 'mcp_servers.brain.command="<abs python3>"' -c
  'mcp_servers.brain.args=["<repo>/synapse/mcp/server.py"]' -c
  'mcp_servers.brain.env={SYNAPSE_BRAINS="<copy>",SYNAPSE_HOME="<tmp>"}' "<brand voice question>"`.
- **Claude Code with synapse disabled**: `env -u SYNAPSE_BRAINS claude -p --strict-mcp-config
  --mcp-config <json> --settings '{"enabledPlugins":{"synapse@brainforge":false}}'
  --output-format stream-json --verbose "<same question>"`.

Pass, per client = the JSONL transcript shows a `brain_map` call, then `brain_read` of a
`context/canon/brand/` file, and the answer cites it and carries the announce line. For Claude
Code, additionally no `brain-routing` skill invocation appears in the stream, so the plugin was
really out of play.
Verify: the transcript excerpts pasted into the proof.

### Step 4 — Docs and version

Files: `synapse/templates/mcp-client-config.md` (new), `synapse/.claude-plugin/plugin.json`,
`README.md`, `ROADMAP.md`
Change:
- Template: how to get the server file (`git clone https://github.com/jrpease/brainforge`;
  `git pull` to update), requirements (macOS/Linux or Git Bash/WSL; `python3`, `git`, `bash`),
  and config snippets for Claude Desktop (`claude_desktop_config.json`), Cursor
  (`.cursor/mcp.json`), Codex (`~/.codex/config.toml`) and a generic `mcpServers` block, each
  with an absolute `python3` path and the `env` block.
- Bump synapse to 0.8.0, before staging.
- README: replace line 60's "An MCP server" non-goal with "A hosted MCP endpoint"; rewrite the
  web-only and Cursor/Codex bullets around line 111–114 to "any local MCP client → the synapse MCP
  server (template link); web-only tools (ChatGPT, Claude.ai) → on the roadmap: a hosted
  endpoint"; change line 219's "Open next" to name the hosted endpoint, not the façade.
- ROADMAP: add a ticked line for the stdio façade (synapse 0.8.0, spec and proof links) and
  narrow the unticked tier-3 line to the hosted endpoint. Under Deferred, change "MCP universal
  reader" to "hosted MCP endpoint".

Verify: `git show HEAD:synapse/.claude-plugin/plugin.json | grep '"version"'` → `0.8.0`; and
`grep -n "An MCP server\|Open next\|tier 3\|universal reader" README.md ROADMAP.md` shows no
line still calling the façade unbuilt or tier 3 shipped.
