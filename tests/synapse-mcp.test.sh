#!/usr/bin/env bash
# synapse MCP server: protocol shape, the map it serves, and the read fence.
# Every assertion addresses a response by its request id, and the line count is asserted, so a
# server that crashed early or answered a notification cannot pass on the strength of
# responses it gave before that.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/synapse/mcp/server.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# A git copy of the eval fixture, as a subscriber would clone it.
BRAIN="$TMP/origin/acme-brain"; mkdir -p "$TMP/origin"
cp -R "$ROOT/evals/fixtures/acme-brain" "$BRAIN"
echo "secret" > "$TMP/secret.md"
echo "x" > "$BRAIN/context/canon/notes.txt"                     # not a type the reader serves
ln -s "$TMP/secret.md" "$BRAIN/context/canon/brand/escape.md"   # a committed symlink out of the brain
(cd "$BRAIN" && git init -q && git add -A && git commit -q -m brain)
mkdir -p "$TMP/home"
for f in "$TMP/origin/outside.md" "$TMP/home/outside.md" "$TMP/outside.md"; do echo "secret" > "$f"; done

# A second brain with no manifest (one that predates v0.4.0).
OLD="$TMP/origin/old-brain"
cp -R "$ROOT/evals/fixtures/acme-brain" "$OLD"; rm "$OLD/.brainforge/brain-manifest.json"
(cd "$OLD" && git init -q && git add -A && git commit -q -m brain)

# session <SYNAPSE_BRAINS> <home> <file of request lines> -> server stdout
session() { SYNAPSE_BRAINS="$1" SYNAPSE_HOME="$2" python3 "$SERVER" < "$3"; }

# check <stdout file> <python assertions over `by` (id -> response) and `lines`>
check() {
  python3 - "$1" "$2" <<'PY' || exit 1
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
by = {r["id"]: r for r in lines}
def res(i): return by[i]["result"]
def txt(i): return res(i)["content"][0]["text"]
def err(i): return res(i).get("isError") is True
try:
    exec(sys.argv[2])
except AssertionError as e:
    print("FAIL:", e); sys.exit(1)
PY
}

req() { python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])))' "$1"; }
call() { req "{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":$3}}"; }
rd() { call "$1" brain_read "{\"brain\":\"$2\",\"path\":\"$3\"}"; }

# ---- Session A: the whole protocol against a healthy brain ----
{
  req '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
  req '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  req '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  call 3 brain_map '{}'
  rd 4 acme-brain context/canon/brand/_index.md
  rd 5 acme-brain context/canon
  rd 6 acme-brain .brainforge/brain-manifest.json
  rd 7 acme-brain ../outside.md
  rd 8 acme-brain "$TMP/origin/outside.md"
  rd 9 acme-brain .git/config
  rd 10 acme-brain context/canon/brand/../../../../outside.md
  rd 11 no-such-brain context/canon/brand/_index.md
  req '{"jsonrpc":"2.0","id":12,"method":"resources/list"}'
  rd 13 acme-brain context/canon/brand/escape.md
  echo '{not json'
} > "$TMP/a.in"
session "$BRAIN" "$TMP/home" "$TMP/a.in" > "$TMP/a.out"

FIXTURE_INDEX="$BRAIN/context/canon/brand/_index.md" check "$TMP/a.out" '
import os
assert len(lines) == 14, f"expected 14 responses (13 ids + parse error), got {len(lines)}"
i = res(1)
assert i["protocolVersion"] == "2025-06-18", "should echo a supported client version"
assert i["serverInfo"]["name"] == "synapse", "serverInfo.name"
assert "Announce" in i["instructions"] and "brain_read" in i["instructions"], "instructions must carry the skill and the tool mapping"
assert not i["instructions"].startswith("---"), "skill frontmatter must be stripped"
assert [t["name"] for t in res(2)["tools"]] == ["brain_map", "brain_read"], "tool list"
assert all("inputSchema" in t and "brain_map first" in t["description"] for t in res(2)["tools"]), "each tool carries a schema and the load-bearing rules"
assert all(t["annotations"]["readOnlyHint"] is True for t in res(2)["tools"]), "both tools declare read-only"
assert "user-facing copy" in res(2)["tools"][0]["description"], "brain_map carries the skill when-to-use trigger"
assert not err(3), "brain_map should succeed"
assert "🧠 acme-brain — brain at" in txt(3), "map header"
assert "\"writing user-facing copy\"" in txt(3), "routing table appended"
assert not err(4) and txt(4) == open(os.environ["FIXTURE_INDEX"], encoding="utf-8").read(), "index read verbatim"
assert not err(5) and "brand/" in txt(5).splitlines(), "directory listing"
assert "notes.txt" not in txt(5), "listing shows only what can be read"
assert not err(6) and "\"contextFingerprint\"" in txt(6), "the manifest is readable"
for n in (7, 8, 9, 10, 11, 13):
    assert err(n), f"id {n} must be refused"
assert "secret" not in "".join(txt(n) for n in (7, 8, 10, 13)), "outside content leaked"
assert by[12]["error"]["code"] == -32601, "unknown method"
pe = [r for r in lines if r["id"] is None]
assert len(pe) == 1 and pe[0]["error"]["code"] == -32700, "parse error"
'

# ---- Session B: a read before any map is refused ----
rd 1 acme-brain context/canon/brand/_index.md > "$TMP/b.in"
session "$BRAIN" "$TMP/home" "$TMP/b.in" > "$TMP/b.out"
check "$TMP/b.out" '
assert len(lines) == 1, "one response"
assert err(1) and "brain_map first" in txt(1), "read before brain_map must be refused"
'

# ---- Session C: a brain with no manifest is still readable ----
{ call 1 brain_map '{}'; rd 2 old-brain context/canon/brand/_index.md; rd 3 old-brain .git/config; } > "$TMP/c.in"
session "$OLD" "$TMP/home" "$TMP/c.in" > "$TMP/c.out"
check "$TMP/c.out" '
assert len(lines) == 3, "three responses"
assert "has no manifest" in txt(1), "map reports the missing manifest"
assert not err(2) and "kinds" in txt(2), "a manifest-less brain reads through the context/ default"
assert err(3), "the fence still holds without a manifest"
'

# ---- Session E: a manifest cannot widen the fence past the brain ----
EVIL="$TMP/origin/evil-brain"
cp -R "$ROOT/evals/fixtures/acme-brain" "$EVIL"
sed -i.bak 's/^  "contextRoot": ".*",$/  "contextRoot": "..\/..",/' "$EVIL/.brainforge/brain-manifest.json"; rm "$EVIL/.brainforge/brain-manifest.json.bak"
grep -q '"contextRoot": "../.."' "$EVIL/.brainforge/brain-manifest.json" || fail "fixture edit did not land"
(cd "$EVIL" && git init -q && git add -A && git commit -q -m brain)
{ call 1 brain_map '{}'; rd 2 evil-brain ../outside.md; call 3 brain_read '{"brain":["x"],"path":"context"}'; } > "$TMP/e.in"
session "$EVIL" "$TMP/home" "$TMP/e.in" > "$TMP/e.out"
check "$TMP/e.out" '
assert len(lines) == 3, "three responses"
assert err(2) and "contextRoot" in txt(2), "an escaping contextRoot must be refused by its own guard"
assert err(3), "a non-string brain is a tool error, not a crash"
'

# ---- Session F: a non-default context root is honoured; "." never exposes .git ----
DOCS="$TMP/origin/docs-brain"
cp -R "$ROOT/evals/fixtures/acme-brain" "$DOCS"; mv "$DOCS/context" "$DOCS/docs"
sed -i.bak 's/^  "contextRoot": ".*",$/  "contextRoot": "docs",/' "$DOCS/.brainforge/brain-manifest.json"; rm "$DOCS/.brainforge/brain-manifest.json.bak"
DOT="$TMP/origin/dot-brain"
cp -R "$ROOT/evals/fixtures/acme-brain" "$DOT"
sed -i.bak 's/^  "contextRoot": ".*",$/  "contextRoot": ".",/' "$DOT/.brainforge/brain-manifest.json"; rm "$DOT/.brainforge/brain-manifest.json.bak"
for b in "$DOCS" "$DOT"; do (cd "$b" && git init -q && git add -A && git commit -q -m brain); done
{
  call 1 brain_map '{}'
  rd 2 docs-brain docs/canon/brand/_index.md
  rd 3 docs-brain context/canon/brand/_index.md
  rd 4 dot-brain .git/config
  rd 5 dot-brain .
  call 6 brain_read '{"brain":"docs-brain","path":"docs/\u0000x"}'
  req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"brain_read","arguments":["x"]}}'
} > "$TMP/f.in"
session "$DOCS,$DOT" "$TMP/home" "$TMP/f.in" > "$TMP/f.out"
check "$TMP/f.out" '
assert len(lines) == 7, "seven responses"
assert not err(2) and "kinds" in txt(2), "a docs/ context root reads through the manifest value"
assert err(3), "the default context/ is not the root when the manifest names another"
assert err(4) and ".git" in txt(4), "a . root never reads .git"
assert not err(5) and ".git/" not in txt(5) and "context/" in txt(5), "a . root never lists .git"
assert err(6), "a NUL in the path is a tool error"
assert by[7]["error"]["code"] == -32602, "non-object arguments are invalid params"
'

# ---- Session G: a hook that dies before its first line is an error, never an empty map ----
call 1 brain_map '{}' > "$TMP/g.in"
env -u HOME -u SYNAPSE_HOME SYNAPSE_BRAINS="$BRAIN" python3 "$SERVER" < "$TMP/g.in" > "$TMP/g.out"
check "$TMP/g.out" '
assert err(1) and "hook failed" in txt(1) and "UNGROUNDED" in txt(1), "a crashed hook must surface as an error"
'

# ---- Session D: nothing subscribed ----
call 1 brain_map '{}' > "$TMP/d.in"
session "" "$TMP/home" "$TMP/d.in" > "$TMP/d.out"
check "$TMP/d.out" '
assert err(1) and "no brains configured" in txt(1), "empty SYNAPSE_BRAINS must be an error, never an empty map"
'

echo PASS
