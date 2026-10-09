#!/usr/bin/env bash
# gate-figma.sh - the Figma cheap change gate (pipeline/adapters/figma.md §1) as a script.
#
# USAGE   bash .brainforge/gate-figma.sh [<source-id>...]      (run from the brain root)
# With ids it gates those entries (plus every enabled entry sharing their fileKey, because the
# state slot is shared); with none it gates every enabled figma entry.
#
# Reads sources.json, .sync-state.json and FIGMA_TOKEN from .env (matched by `^FIGMA_TOKEN=`,
# never sourced). Read-only: it never writes .sync-state.json. One REST call per fileKey.
#
# OUTPUT  one JSON object per gated entry, one per line:
#   {"type":"figma","id":..,"status":"unchanged|changed|never|not-checked|blocked","reason":..,
#    "fingerprint":{"version":..,"lastModified":..},"stored":{..}|null,"delta":[]}
# `never` = no stored slot, or the entry's `into` holds no files yet (extract regardless).
# `blocked` = the entry has no `into:`.
# EXIT    0 gated; 1 misuse (unknown id, no sources.json) or no python3, message on stderr.
set -u

if ! command -v python3 > /dev/null 2>&1; then
  echo "✗ gate-figma: python3 not found." >&2; exit 1
fi
if [ ! -f sources.json ]; then
  echo "✗ gate-figma: no sources.json in $(pwd) (run from the brain root)." >&2; exit 1
fi

FIGMA_TOKEN=""
if [ -f .env ]; then
  FIGMA_TOKEN=$(grep -m1 '^FIGMA_TOKEN=' .env | sed 's/^FIGMA_TOKEN=//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/' || true)
fi
export FIGMA_TOKEN

exec python3 - "$@" <<'PY'
import json, os, subprocess, sys, tempfile

def die(msg):
    sys.stderr.write("✗ gate-figma: " + msg + "\n"); sys.exit(1)

try:
    sources = json.load(open("sources.json"))
except Exception as e:
    die("cannot read sources.json (%s)" % e)
try:
    state = json.load(open(".sync-state.json")).get("figma", {}) or {}
except Exception:
    state = {}

entries = sources.get("figma", []) or []
by_id = {e.get("id"): e for e in entries}
ids = sys.argv[1:]
for i in ids:
    if i not in by_id:
        die("unknown figma source id: %s" % i)

if ids:
    keys = {by_id[i].get("fileKey") for i in ids}
    selected = [e for e in entries
                if e.get("id") in ids or (e.get("enabled", True) is not False and e.get("fileKey") in keys)]
else:
    selected = [e for e in entries if e.get("enabled", True) is not False]

def out(e, status, reason=None, fp=None, stored=None):
    print(json.dumps({"type": "figma", "id": e.get("id"), "status": status, "reason": reason,
                      "fingerprint": fp, "stored": stored, "delta": []}))

def has_output(into):
    if not into or not os.path.isdir(into):
        return False
    return any(files for _, _, files in os.walk(into))

groups = {}
for e in selected:
    groups.setdefault(e.get("fileKey"), []).append(e)

token = os.environ.get("FIGMA_TOKEN", "")
for key, group in groups.items():
    slot = state.get(key)
    stored = None
    if isinstance(slot, dict) and slot.get("version"):
        stored = {"version": slot.get("version"), "lastModified": slot.get("lastModified")}
    live = []
    for e in group:
        if not e.get("into"):
            out(e, "blocked", "no into: set on this entry", None, stored)
        elif stored is None:
            out(e, "never", "no stored version", None, None)
        elif not has_output(e["into"]):
            out(e, "never", "into holds no output yet", None, stored)
        else:
            live.append(e)
    if not live:
        continue
    if not token:
        for e in live:
            out(e, "not-checked", "no credentials", None, stored)
        continue
    fd, path = tempfile.mkstemp(); os.close(fd)
    try:
        r = subprocess.run(["curl", "-s", "--max-time", "30", "-H", "X-Figma-Token: " + token, "-o", path,
                            "-w", "%{http_code}",
                            "https://api.figma.com/v1/files/%s?depth=1" % key],
                           capture_output=True, text=True)
        code = r.stdout.strip()
        body = open(path).read()
    finally:
        os.unlink(path)
    if r.returncode != 0:
        for e in live:
            out(e, "not-checked", "offline", None, stored)
        continue
    fp = None
    if code == "200":
        try:
            d = json.loads(body)
            if d.get("version"):
                fp = {"version": d.get("version"), "lastModified": d.get("lastModified")}
        except ValueError:
            pass
    if fp is None:
        reason = ("HTTP %s" % code) if code != "200" else "unparseable response (HTTP 200)"
        for e in live:
            out(e, "not-checked", reason, None, stored)
        continue
    status = "unchanged" if fp["version"] == stored["version"] else "changed"
    for e in live:
        out(e, status, None, fp, stored)
PY
