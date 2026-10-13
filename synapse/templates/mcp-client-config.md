# Read a brain from any MCP client (Claude Desktop, Cursor, Codex, VS Code, …)

Claude Code users get the brain through the synapse plugin. Every other client that speaks MCP
over stdio gets it through `synapse/mcp/server.py`: the same map, the same routing rules and the
same loud failures, served as two read-only tools, `brain_map` and `brain_read`.

Proven live in Codex and Claude Code ([proof](../../docs/proofs/mcp-facade.md)). The other
clients below use the standard MCP config shape and have not been run against it yet.

**Requirements:** macOS or Linux (Windows only under Git Bash or WSL), with `python3`, `git` and
`bash` on the machine. Nothing to `pip install`. Your git credentials must be able to clone the
brain, exactly as for the plugin.

## 1. Get the server

```bash
git clone https://github.com/jrpease/brainforge ~/brainforge
```

Update it with `git -C ~/brainforge pull`. The brains themselves update on their own: every
`brain_map` call pulls them, with an 8-second network bound.

## 2. Add it to your client

Find your interpreter's absolute path with `command -v python3`. Use it below: desktop clients
start servers with a short `PATH`, so a bare `python3` may not be found. Replace `/Users/you` and
the brain URL. Several brains go in one comma-separated `SYNAPSE_BRAINS`.

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`) and
**Cursor** (`~/.cursor/mcp.json`, or `.cursor/mcp.json` in one repo) use the same block:

```json
{
  "mcpServers": {
    "brain": {
      "command": "/usr/local/bin/python3",
      "args": ["/Users/you/brainforge/synapse/mcp/server.py"],
      "env": { "SYNAPSE_BRAINS": "git@github.com:your-org/your-brain.git" }
    }
  }
}
```

**Codex** (`~/.codex/config.toml`):

```toml
[mcp_servers.brain]
command = "/usr/local/bin/python3"
args = ["/Users/you/brainforge/synapse/mcp/server.py"]
env = { SYNAPSE_BRAINS = "git@github.com:your-org/your-brain.git" }
```

**VS Code** (`.vscode/mcp.json`): the same entry, under a `servers` key instead of `mcpServers`.

**Any other client:** command `python3` (absolute path), one argument (the path to `server.py`),
and `SYNAPSE_BRAINS` in the server's environment.

Optional variables, the same as the plugin's: `SYNAPSE_HOME` (where brains are cloned, default
`~/.synapse`, shared with Claude Code if you use both) and `SYNAPSE_NET_TIMEOUT` (seconds, default
8).

## 3. Tell the client to use it

Some clients reach for the brain on their own; Claude Code did in the
[live proof](../../docs/proofs/mcp-facade.md), and Codex did not. Add this to the project's rules
file (`AGENTS.md`, `.cursor/rules`, or equivalent) so it always does:

```markdown
Before answering anything that touches brand voice, copy, naming, design, product principles,
metrics or other org facts, call the `brain_map` tool and follow its instructions.
```

## Check it works

Ask a brand or product question. The answer should cite brain files and end with a line like
`🧠 loaded: Brand · skipped: none`. If `brain_map` says `UNAVAILABLE`, the clone failed: check
that `git clone <your brain URL>` works in a terminal.
