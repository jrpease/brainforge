#!/usr/bin/env python3
"""synapse MCP server: the same brain reader as the plugin, for any local MCP client.

Read-only. stdio transport: one JSON-RPC 2.0 message per line in, one per line out; logs go to
stderr only, because stdout is the protocol. Stdlib only, so a stranger never runs pip.

It is a facade, not a second reader. The map is whatever synapse/hooks/session-start.sh prints
(clone/pull, collisions, staleness, coverage, every loud failure line), and the routing rules
are synapse/skills/brain-routing/SKILL.md served verbatim as the server's instructions. A
routing change therefore reaches this server and the plugin by the same update.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent
PROTOCOL_VERSIONS = ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25")

# The two map lines that name a brain and its directory. The hook owns directory choice
# (collision suffixes exist), so the server never reconstructs a path from a name.
HEADER = re.compile(r"^🧠 (\S+) — brain at (.+) \(last change")
NO_MANIFEST = re.compile(r"^🧠 synapse: (\S+) has no manifest — read (.+)/context/ directly")
CONTEXT_ROOT = re.compile(r'^  "contextRoot": "(.*)",$', re.M)

# Both tools change nothing a client cares about: the only write is the hook's clone/pull
# under SYNAPSE_HOME, a mirror of the org's own brains. Saying so lets clients that gate
# tool calls on approval (Codex in exec mode refuses an unannotated call) run them.
READ_ONLY = {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False}

RULES = (
    "Call brain_map first, once per conversation. Read brain content only through brain_read, "
    "using a brain name the map printed. End every grounded answer with the announce line "
    "`🧠 loaded: <domain titles> · skipped: <notable skipped domains or none>`."
)

PREAMBLE = f"""# synapse: read the org's brain

{RULES}

This server is the MCP form of the synapse brain-routing skill below. Where the skill names a
file, use the tools:

- The session map the skill refers to is the output of `brain_map`. It renders each brain's
  manifest. The routing table the skill reads from `${{CLAUDE_PLUGIN_ROOT}}/routing/intents.json`
  is printed at the end of `brain_map`.
- Every file the skill says to read (the manifest, an `_index.md`, a content file) is
  `brain_read(brain, path)`, with the brain name from the map and a path relative to that brain,
  e.g. `context/canon/brand/_index.md` or `.brainforge/brain-manifest.json`. A directory path
  lists its entries.
- The brains this server serves are the ones `brain_map` prints. A brain open in your own
  workspace is outside this server; do not mix the two silently.

"""

SKILL = PLUGIN / "skills/brain-routing/SKILL.md"


def skill_parts():
    """(when-to-use description, body) of the brain-routing skill. Claude Code reads the
    description to decide when to load the skill; an MCP client sees only tool descriptions,
    so the same sentence goes there, or the model never thinks to open the brain."""
    skill = SKILL.read_text(encoding="utf-8")
    when = ""
    if skill.startswith("---\n"):
        end = skill.find("\n---\n", 4)
        if end != -1:
            m = re.search(r"^description: (.+)$", skill[4:end], re.M)
            when = m.group(1).strip() if m else ""
            skill = skill[end + 5 :]
    return when, skill.lstrip("\n")


WHEN, BODY = skill_parts()

TOOLS = [
    {
        "name": "brain_map",
        "description": "Read the organisation's brain: its authored canon and synced facts. "
        + WHEN + " Returns the map of subscribed brains (domains, kinds, size bands, freshness "
        "warnings) and the routing table of intents to kinds. " + RULES,
        "inputSchema": {"type": "object", "properties": {}},
        "annotations": {"title": "Brain map", **READ_ONLY},
    },
    {
        "name": "brain_read",
        "description": "Read one file, or list one directory, from a brain: an `_index.md` "
        "first, then only the files it shows you need. `path` is relative to the brain, e.g. "
        "`context/canon/brand/_index.md`. " + RULES,
        "inputSchema": {
            "type": "object",
            "properties": {
                "brain": {"type": "string", "description": "A brain name as printed by brain_map."},
                "path": {"type": "string", "description": "Path relative to that brain."},
            },
            "required": ["brain", "path"],
        },
        "annotations": {"title": "Read from the brain", **READ_ONLY},
    },
]


class MethodNotFound(Exception):
    pass


class InvalidParams(Exception):
    pass


brains = None  # name -> Path, from the latest brain_map; None until one has run


def instructions():
    return PREAMBLE + "When to use: " + WHEN + "\n\n" + BODY


def version():
    meta = json.loads((PLUGIN / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
    return meta["version"]


def text(s, error=False):
    result = {"content": [{"type": "text", "text": s}]}
    if error:
        result["isError"] = True
    return result


def brain_map():
    global brains
    if not os.environ.get("SYNAPSE_BRAINS", "").strip():
        return text("no brains configured: set SYNAPSE_BRAINS in this server's env", error=True)
    try:
        # Every network call in the hook is bounded; this bounds anything else that could block.
        run = subprocess.run(
            ["bash", str(PLUGIN / "hooks/session-start.sh")],
            capture_output=True,
            stdin=subprocess.DEVNULL,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        return text("the synapse hook timed out after 300s; proceeding UNGROUNDED", error=True)
    out = run.stdout.decode("utf-8", errors="replace")
    brains = {}
    for line in out.splitlines():
        m = HEADER.match(line) or NO_MANIFEST.match(line)
        if m:
            brains[m.group(1)] = Path(m.group(2))
    # An empty map must never read as a successful one: a hook that died before its first
    # line (no HOME in a sparse spawn env, say) would otherwise look like a brain-less success.
    if run.returncode != 0 or "🧠" not in out:
        why = run.stderr.decode("utf-8", errors="replace").strip().splitlines()
        return text(
            f"the synapse hook failed (exit {run.returncode}): {why[0] if why else 'no output'}; "
            "proceeding UNGROUNDED\n" + out,
            error=True,
        )
    table = (PLUGIN / "routing/intents.json").read_text(encoding="utf-8")
    return text(out.rstrip("\n") + "\n\nRouting table (intents → kinds):\n" + table)


def inside(path, root):
    return path == root or root in path.parents


def brain_read(brain, path):
    if brains is None:
        return text("call brain_map first", error=True)
    if not isinstance(brain, str) or brain not in brains:
        known = ", ".join(sorted(brains)) or "none"
        return text(f"unknown brain {brain!r}; brains in the map: {known}", error=True)
    if not isinstance(path, str) or not path or os.path.isabs(path):
        return text("path must be relative to the brain, e.g. context/canon/brand/_index.md", error=True)
    base = brains[brain].resolve()
    manifest = base / ".brainforge/brain-manifest.json"
    root = "context"
    if manifest.is_file():
        m = CONTEXT_ROOT.search(manifest.read_text(encoding="utf-8"))
        if m and m.group(1):
            root = m.group(1)
    ctx = (base / root).resolve()
    if not inside(ctx, base):  # the manifest is brain data; it never widens the fence past the brain
        return text(f"the manifest's contextRoot {root!r} is outside the brain; refusing to read", error=True)
    try:
        target = (base / path).resolve()
    except (ValueError, OSError) as e:
        return text(f"unreadable path {path!r}: {e}", error=True)
    if inside(target, base) and ".git" in target.relative_to(base).parts:
        return text("the brain's .git directory is not part of its reference", error=True)
    if target != manifest and not inside(target, ctx):
        return text(f"outside the brain's reference: only {root}/ and .brainforge/brain-manifest.json can be read", error=True)
    if target.is_dir():
        entries = sorted(
            e.name + "/" if e.is_dir() else e.name
            for e in target.iterdir()
            if (e.is_dir() and e.name != ".git") or e.suffix in (".md", ".json")
        )
        return text("\n".join(entries))
    if not target.is_file():
        return text(f"not found: {path}", error=True)
    if target.suffix not in (".md", ".json"):
        return text("only .md and .json files can be read", error=True)
    return text(target.read_text(encoding="utf-8", errors="replace"))


def call(name, args):
    if name == "brain_map":
        return brain_map()
    if name == "brain_read":
        return brain_read(args.get("brain"), args.get("path"))
    return text(f"unknown tool {name!r}", error=True)


def handle(msg):
    method = msg.get("method")
    params = msg.get("params") or {}
    if not isinstance(params, dict):
        raise InvalidParams("params must be an object")
    if method == "initialize":
        asked = params.get("protocolVersion")
        return {
            "protocolVersion": asked if asked in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[-1],
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "synapse", "version": version()},
            "instructions": instructions(),
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        args = params.get("arguments") or {}
        if not isinstance(args, dict):
            raise InvalidParams("arguments must be an object")
        return call(params.get("name"), args)
    raise MethodNotFound(method)


def send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    stdin = open(sys.stdin.fileno(), encoding="utf-8", errors="replace", closefd=False)
    for line in stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            try:
                send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}})
            except BrokenPipeError:
                return
            continue
        if not isinstance(msg, dict) or "id" not in msg:
            continue  # a notification: no response
        try:
            send({"jsonrpc": "2.0", "id": msg["id"], "result": handle(msg)})
            continue
        except BrokenPipeError:
            return  # the client has gone; nothing left to answer
        except MethodNotFound as e:
            error = {"code": -32601, "message": f"method not found: {e}"}
        except InvalidParams as e:
            error = {"code": -32602, "message": str(e)}
        except Exception as e:  # never die mid-session; the client gets the reason
            print(f"synapse mcp: {e!r}", file=sys.stderr)
            error = {"code": -32603, "message": str(e)}
        try:
            send({"jsonrpc": "2.0", "id": msg["id"], "error": error})
        except BrokenPipeError:
            return


if __name__ == "__main__":
    main()
