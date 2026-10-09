#!/usr/bin/env bash
# gate-github.sh — the cheap change gate for code repos (pipeline/adapters/github.md §0b, §1),
# as a script instead of prose.
#
# For each gated `repos[]` entry it:
#   1. finds the clone (`localClone`); none → not-checked (no clone)
#   2. checks the clone's origin names the entry's `remote` (host/org/repo, ignoring scheme,
#      user@ and a trailing .git) → blocked on mismatch, before any fetch
#   3. `git fetch --quiet origin` (no prompts); failure → not-checked (offline)
#   4. applies `.brainforge-source.yml` read from origin/<branch> (never the working tree) with a
#      strict parser for the documented subset; anything else → blocked (fail closed)
#   5. no stored lastSha → never
#   6. lastSha missing from, or not an ancestor of, origin/<branch> → blocked
#   7. diffs lastSha..origin/<branch>, filters through the declaration, and reports the in-scope
#      paths as `delta` plus an `excluded` count. Excluded paths are never named.
#
# Read-only: it never writes .sync-state.json and never checks out or pulls.
#
# USAGE (from the brain root)
#   bash .brainforge/gate-github.sh [<source-id>…]   no ids = every enabled repos[] entry
#
# OUTPUT  one JSON object per gated entry, one per line (JSON Lines):
#   {"type":"github","id":…,"status":"unchanged|changed|never|not-checked|blocked","reason":…,
#    "fingerprint":{"lastSha":…},"stored":{"lastSha":…}|null,"delta":[…],"excluded":N}
#
# EXIT
#   0  results printed (whatever their status)
#   1  misuse: an unknown id, no or unreadable sources.json, or no python3 (stderr says which)
set -u

case "${1:-}" in -h|--help) sed -n '2,29p' "$0"; exit 0 ;; esac

if ! command -v python3 > /dev/null 2>&1; then
  echo "gate-github: python3 not found" >&2
  exit 1
fi

python3 - "$@" <<'PY'
import json, os, re, subprocess, sys

def out(entry_id, status, reason=None, fingerprint=None, stored=None, delta=None, excluded=None):
    print(json.dumps({"type": "github", "id": entry_id, "status": status, "reason": reason,
                      "fingerprint": fingerprint, "stored": stored, "delta": delta if delta is not None else [],
                      "excluded": excluded if excluded is not None else 0}), flush=True)

def die(msg):
    sys.stderr.write("gate-github: " + msg + "\n")
    sys.exit(1)

try:
    with open("sources.json") as f:
        sources = json.load(f)
except FileNotFoundError:
    die("no sources.json here; run from the brain root")
except Exception as e:
    die("sources.json unreadable: %s" % e)

try:
    with open(".sync-state.json") as f:
        state = json.load(f)
except Exception:
    state = {}

repos = [e for e in (sources.get("repos") or []) if isinstance(e, dict)]
ids = sys.argv[1:]
if ids:
    by_id = {e.get("id"): e for e in repos}
    unknown = [i for i in ids if i not in by_id]
    if unknown:
        die("unknown repos id(s): " + ", ".join(unknown))
    entries = [by_id[i] for i in ids]
else:
    entries = [e for e in repos if e.get("enabled", True) is not False]

GIT_ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0",
               GIT_SSH_COMMAND=(os.environ.get("GIT_SSH_COMMAND") or "ssh") + " -oBatchMode=yes")

def git(clone, *args):
    try:
        return subprocess.run(["git", "-C", clone] + list(args), capture_output=True, text=True,
                              env=GIT_ENV, timeout=120)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "timed out")

def norm_remote(url):
    u = (url or "").strip()
    had_scheme = bool(re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", u))
    u = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://", "", u)   # scheme
    u = re.sub(r"^[^@/]+@", "", u)                       # user@
    if had_scheme:
        u = re.sub(r"^([^/:]+):\d+/", r"\1/", u)         # ssh://host:port/
    else:
        u = re.sub(r"^([^/:]+):", r"\1/", u)             # scp-style host:org/repo
    u = u.rstrip("/")
    if u.endswith(".git"):
        u = u[:-4]
    parts = u.split("/")
    if parts and parts[0]:
        parts[0] = parts[0].lower()
    return "/".join(parts)

def glob_re(g):
    rx, i = "", 0
    while i < len(g):
        if g.startswith("**", i):
            rx += ".*"; i += 2
        elif g[i] == "*":
            rx += "[^/]*"; i += 1
        elif g[i] == "?":
            rx += "[^/]"; i += 1
        else:
            rx += re.escape(g[i]); i += 1
    return re.compile(rx + r"\Z")

class Malformed(Exception):
    pass

def parse_scope(text):
    """Strict parser for the documented .brainforge-source.yml subset. Raises Malformed."""
    version, lists, current = None, {}, None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r'^(\s*)-\s+("([^"\\]*)"|\'([^\']*)\')\s*(#.*)?$', line)
        if m:
            if current is None:
                raise Malformed("line %d: list item outside a list" % n)
            g = m.group(3) if m.group(3) is not None else m.group(4)
            if not g:
                raise Malformed("line %d: empty glob" % n)
            lists[current].append(g)
            continue
        m = re.match(r'^([A-Za-z-]+):\s*([^#\s][^#]*?)?\s*(#.*)?$', line)
        if not m:
            raise Malformed("line %d: not in the supported subset" % n)
        key, val = m.group(1), m.group(2)
        if key == "version":
            if version is not None:
                raise Malformed("line %d: version given twice" % n)
            if val != "1":
                raise Malformed("line %d: unknown version %r" % (n, val))
            version, current = 1, None
        elif key in ("never-summarize", "summarize"):
            if key in lists:
                raise Malformed("line %d: %s given twice" % (n, key))
            lists[key] = []
            if val is None:
                current = key
            elif val == "[]":
                current = None
            else:
                raise Malformed("line %d: %s must be a block list of quoted globs" % (n, key))
        else:
            raise Malformed("line %d: unknown key %r" % (n, key))
    if version is None:
        raise Malformed("no version")
    never = [glob_re(g) for g in lists.get("never-summarize", [])]
    only = [glob_re(g) for g in lists["summarize"]] if "summarize" in lists else None
    return never, only

def in_scope(path, never, only):
    if any(r.match(path) for r in never):
        return False
    if only is not None and not any(r.match(path) for r in only):
        return False
    return True

repo_state = state.get("repos") if isinstance(state.get("repos"), dict) else {}

for e in entries:
    eid = e.get("id")
    slot = repo_state.get(eid) if isinstance(repo_state.get(eid), dict) else None
    last = slot.get("lastSha") if slot else None
    stored = {"lastSha": last} if last else None
    branch = e.get("branch") or "main"

    clone = e.get("localClone")
    if not clone or git(clone, "rev-parse", "--git-dir").returncode != 0:
        out(eid, "not-checked", "no clone", stored=stored); continue

    origin = git(clone, "config", "--get", "remote.origin.url").stdout.strip()
    if not origin or norm_remote(origin) != norm_remote(e.get("remote")):
        out(eid, "blocked", "origin %s does not match remote %s" % (origin or "(none)", e.get("remote")),
            stored=stored); continue

    if git(clone, "fetch", "--quiet", "origin").returncode != 0:
        out(eid, "not-checked", "offline", stored=stored); continue

    ref = "origin/" + branch
    head = git(clone, "rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if head.returncode != 0:
        out(eid, "blocked", "branch %s not on origin" % branch, stored=stored); continue
    fingerprint = {"lastSha": head.stdout.strip()}

    yml = git(clone, "show", ref + ":.brainforge-source.yml")
    never, only = [], None
    if yml.returncode == 0:
        try:
            never, only = parse_scope(yml.stdout)
        except Malformed as m:
            out(eid, "blocked", ".brainforge-source.yml unparseable: %s" % m, stored=stored); continue
    elif git(clone, "cat-file", "-e", ref + ":.brainforge-source.yml").returncode == 0:
        out(eid, "blocked", ".brainforge-source.yml unreadable", stored=stored); continue

    if not last:
        out(eid, "never", fingerprint=fingerprint); continue

    if (not re.fullmatch(r"[0-9a-fA-F]{7,64}", last)
            or git(clone, "cat-file", "-e", last + "^{commit}").returncode != 0
            or git(clone, "merge-base", "--is-ancestor", last, ref).returncode != 0):
        out(eid, "blocked", "lastSha not in fetched history", fingerprint=fingerprint, stored=stored)
        continue

    diff = git(clone, "diff", "--name-only", last + ".." + ref)
    if diff.returncode != 0:
        out(eid, "blocked", "git diff failed", fingerprint=fingerprint, stored=stored); continue
    changed = [p for p in diff.stdout.splitlines() if p]
    delta = [p for p in changed if in_scope(p, never, only)]
    out(eid, "changed" if delta else "unchanged", fingerprint=fingerprint, stored=stored,
        delta=delta, excluded=len(changed) - len(delta))
PY
