#!/usr/bin/env bash
# source-signal.sh — keep one standing "Sync needed: <id>" issue in the brain current for a
# GitHub source (pipeline/adapters/github.md, "Source-side trigger"). Run by the source repo's
# workflow (templates/source-sync-trigger.yml) on each push; it never syncs, it only makes a
# needed sync visible.
#
# It runs this brain's own gate-github.sh against the source checkout, so the issue says exactly
# what /sync-health would say. Per gate status:
#   changed      open the issue, or edit the open one: in-scope paths, heads, a compare link
#   blocked      open or edit, carrying the reason (a person has to act)
#   unchanged    close the open issue with a "caught up" comment; none open → nothing to do
#   never        nothing to do (the first sync is a person's job); no gh call
#   not-checked  exit 1, so the run goes red; no gh call
# The open issue is found through the REST issues list (label filter, exact title), never through
# search: GitHub's search index lags a fresh create, and a lagging lookup would open a duplicate.
# `gh issue list --label` is search-backed too, so it is not used.
#
# USAGE (from the brain root)
#   bash .brainforge/source-signal.sh <source-id> --clone <path-to-source-checkout>
#   The flag may come before or after the id. gh must be authenticated for the brain repo
#   (GH_TOKEN, and GH_REPO=<owner>/<brain> when the cwd's origin is not the brain).
#
# OUTPUT  one line saying what it did: opened #n | updated #n | closed #n | nothing to do (…)
# EXIT    0 handled; 1 not-checked, a gh failure, the gate failing, or misuse (stderr says which)
set -u
command -v python3 >/dev/null 2>&1 || { echo "source-signal: python3 not found" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
exec python3 - "$here/gate-github.sh" "$@" <<'PY'
import json, os, re, subprocess, sys

LABEL = "brainforge-sync"
MAX_LISTED = 50

BRAIN = os.environ.get("GH_REPO") or os.getcwd()

def die(msg):
    # a red run lands in the source team's CI: name the brain so they know whose problem it is
    sys.stderr.write("source-signal (brain %s): %s\n" % (BRAIN, msg))
    sys.exit(1)

gate_path, args = sys.argv[1], sys.argv[2:]
if "--clone" not in args:
    die("usage: source-signal.sh <source-id> --clone <path>")
i = args.index("--clone")
if i + 1 >= len(args):
    die("--clone needs a path")
clone = args[i + 1]
rest = args[:i] + args[i + 2:]
if len(rest) != 1:
    die("exactly one source id")
sid = rest[0]
title = "Sync needed: %s" % sid

g = subprocess.run(["bash", gate_path, "--clone", clone, sid], capture_output=True, text=True)
lines = [l for l in g.stdout.splitlines() if l.strip()]
if g.returncode != 0 or not lines:
    die("gate failed: %s" % (g.stderr.strip() or "no output"))
try:
    r = json.loads(lines[0])
except ValueError:
    die("gate printed no JSON: %s" % lines[0][:200])
status, reason = r.get("status"), r.get("reason")

if status == "never":
    print("nothing to do (never synced: the first sync is a person's job)")
    sys.exit(0)
if status == "not-checked":
    die("not-checked (%s): the gate could not check this source" % reason)

def gh(*a, body=None):
    p = subprocess.run(["gh"] + list(a), input=body, capture_output=True, text=True)
    if p.returncode != 0:
        die("gh %s failed: %s" % (" ".join(a[:2]), p.stderr.strip()))
    return p.stdout

# REST, not search (see the header); the issues list includes pull requests, so drop those
found = json.loads(gh("api", "repos/{owner}/{repo}/issues?labels=%s&state=open&per_page=100" % LABEL)
                   or "[]")
number = next((x["number"] for x in found
               if "pull_request" not in x and x.get("title") == title), None)

head = (r.get("fingerprint") or {}).get("lastSha")
synced = (r.get("stored") or {}).get("lastSha")

if status == "unchanged":
    if number is None:
        print("nothing to do (caught up, no open issue)")
    else:
        gh("issue", "close", str(number), "--comment", "Caught up at `%s`." % head)
        print("closed #%d" % number)
    sys.exit(0)

def github_slug(remote):
    """owner/repo when remote names github.com in any form the gate accepts, else None."""
    u = (remote or "").strip()
    u = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://", "", u)
    u = re.sub(r"^[^@/]+@", "", u)
    u = re.sub(r"^github\.com:", "github.com/", u)
    m = re.match(r"^github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$", u)
    return "%s/%s" % m.groups() if m else None

try:
    entry = next((e for e in json.load(open("sources.json")).get("repos") or []
                  if isinstance(e, dict) and e.get("id") == sid), {})
except Exception:
    entry = {}
branch = entry.get("branch") or "main"
slug = github_slug(entry.get("remote"))

if status == "changed":
    delta = r.get("delta") or []
    body = ["**%s** has in-scope changes the brain has not synced." % sid, "",
            "- Synced at: `%s`" % synced, "- Source head: `%s` (`%s`)" % (head, branch)]
    if slug and synced and head:
        body.append("- Compare: https://github.com/%s/compare/%s...%s" % (slug, synced, head))
    body += ["", "Changed in scope (%d):" % len(delta)]
    body += ["- `%s`" % p for p in delta[:MAX_LISTED]]
    if len(delta) > MAX_LISTED:
        body.append("- and %d more" % (len(delta) - MAX_LISTED))
    body += ["", "Run `/sync` in the brain to bring this source current."]
else:  # blocked
    body = ["**%s** cannot be checked: %s." % (sid, reason), "",
            "A person has to fix this before the brain can sync it; the gate reports `blocked` "
            "and will keep doing so until then. Run `/sync-health` in the brain for detail."]
body += ["", "<sub>Kept current by `.brainforge/source-signal.sh` on each push to the source. "
         "Closes when the source is caught up.</sub>"]
text = "\n".join(body) + "\n"

if number is None:
    gh("label", "create", LABEL, "--force", "--color", "C5DEF5",
       "--description", "A source changed since the brain last synced it")
    url = gh("issue", "create", "--title", title, "--label", LABEL, "--body-file", "-", body=text)
    m = re.search(r"/issues/(\d+)", url)
    print("opened #%s" % (m.group(1) if m else "?"))
else:
    gh("issue", "edit", str(number), "--body-file", "-", body=text)
    print("updated #%d" % number)
PY
