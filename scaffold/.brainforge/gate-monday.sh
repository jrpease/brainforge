#!/usr/bin/env bash
# gate-monday.sh — Monday's cheap change gate (pipeline/adapters/monday.md §1), as a script.
#
# One GraphQL call covers every board it gates (golden rule 1):
#   query ($ids:[ID!]) { boards (ids:$ids) { id updated_at items_count activity_logs (limit:1) { created_at } } }
# Fingerprint per board = {updated_at, items_count, lastActivityAt}. lastActivityAt is the newest
# activity event's created_at (an opaque string), or null when there is none. Any field differing
# from the stored slot puts the board in the delta. A stored slot with no lastActivityAt key (every
# slot written before the widened fingerprint) reports `changed` once. The widened fingerprint is
# unconfirmed until live check L1 runs.
#
# Read-only: it never writes .sync-state.json. §3 stores `fingerprint` verbatim.
#
# USAGE
#   bash .brainforge/gate-monday.sh [<source-id>...]
#   Run from the brain root. With ids it gates those entries; with none, every enabled monday entry.
#   Reads sources.json -> monday[], .sync-state.json -> monday[<boardId>], and MONDAY_API_TOKEN
#   from .env (matched as ^MONDAY_API_TOKEN=, never sourced).
#
# OUTPUT  one JSON object per gated entry, one per line:
#   {"type":"monday","id":...,"status":...,"reason":...,"fingerprint":...,"stored":...,"delta":[...]}
#   status: unchanged | changed | never | not-checked | blocked. `delta` names the fingerprint
#   fields that moved. A GraphQL `errors` array makes every entry in the call not-checked, with the
#   first error message as the reason.
# EXIT    0 gated (whatever the statuses); 1 misuse: no sources.json, an unknown id, or no python3.
set -u

case "${1:-}" in -h|--help) sed -n '2,27p' "$0"; exit 0 ;; esac

if ! command -v python3 > /dev/null 2>&1; then
  echo "✗ gate-monday: python3 not found." >&2
  exit 1
fi
if [ ! -f sources.json ]; then
  echo "✗ gate-monday: no sources.json here; run from the brain root." >&2
  exit 1
fi

exec python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, tempfile

ENDPOINT = "https://api.monday.com/v2"
QUERY = ("query ($ids:[ID!]) { boards (ids:$ids) { id updated_at items_count "
         "activity_logs (limit:1) { created_at } } }")
FIELDS = ("updated_at", "items_count", "lastActivityAt")

def die(msg):
    print("✗ gate-monday: " + msg, file=sys.stderr)
    sys.exit(1)

try:
    with open("sources.json") as f:
        entries = json.load(f).get("monday") or []
except (OSError, ValueError) as e:
    die("cannot read sources.json (%s)" % e)

ids = sys.argv[1:]
if ids:
    by_id = {e.get("id"): e for e in entries}
    unknown = [i for i in ids if i not in by_id]
    if unknown:
        die("unknown monday source id: " + ", ".join(unknown))
    gated = [by_id[i] for i in ids]
else:
    gated = [e for e in entries if e.get("enabled", True) is not False]

try:
    with open(".sync-state.json") as f:
        state = json.load(f).get("monday") or {}
except (OSError, ValueError):
    state = {}

def emit(entry, status, reason=None, fingerprint=None, stored=None, delta=None):
    print(json.dumps({"type": "monday", "id": entry.get("id"), "status": status,
                      "reason": reason, "fingerprint": fingerprint, "stored": stored,
                      "delta": delta or []}))

def stored_for(entry):
    slot = state.get(str(entry.get("boardId")))
    return slot if isinstance(slot, dict) else None

def all_not_checked(reason):
    for e in gated:
        emit(e, "not-checked", reason, stored=stored_for(e))
    sys.exit(0)

if not gated:
    sys.exit(0)

token = None
try:
    with open(".env") as f:
        for line in f:
            m = re.match(r"^MONDAY_API_TOKEN=(.*)$", line.rstrip("\r\n"))
            if m:
                token = m.group(1).strip()
                if len(token) >= 2 and token[0] == token[-1] and token[0] in "\"'":
                    token = token[1:-1]
except OSError:
    pass
if not token:
    all_not_checked("no credentials")

board_ids = []
for e in gated:
    b = str(e.get("boardId"))
    if b not in board_ids:
        board_ids.append(b)
payload = json.dumps({"query": QUERY, "variables": {"ids": board_ids}})

fd, out_path = tempfile.mkstemp()
os.close(fd)
try:
    try:
        r = subprocess.run(["curl", "-s", "--max-time", "30", "-X", "POST", ENDPOINT,
                            "-H", "Authorization: " + token,
                            "-H", "Content-Type: application/json",
                            "-d", payload, "-o", out_path, "-w", "%{http_code}"],
                           capture_output=True, text=True)
    except OSError:
        all_not_checked("offline")
    if r.returncode != 0:
        all_not_checked("offline")
    code = r.stdout.strip()
    with open(out_path) as f:
        raw = f.read()
finally:
    os.unlink(out_path)

if code != "200":
    all_not_checked("HTTP %s" % code)
try:
    resp = json.loads(raw)
except ValueError:
    all_not_checked("unparseable response")
if not isinstance(resp, dict):
    all_not_checked("unparseable response")
errors = resp.get("errors")
if errors:
    first = errors[0] if isinstance(errors, list) else errors
    msg = first.get("message") if isinstance(first, dict) else str(first)
    all_not_checked("GraphQL error: %s" % (msg or "unknown"))

boards = {}
for b in ((resp.get("data") or {}).get("boards") or []):
    if isinstance(b, dict):
        boards[str(b.get("id"))] = b

for e in gated:
    stored = stored_for(e)
    b = boards.get(str(e.get("boardId")))
    if b is None:
        emit(e, "not-checked", "board not in response", stored=stored)
        continue
    logs = b.get("activity_logs") or []
    last = logs[0].get("created_at") if logs and isinstance(logs[0], dict) else None
    fp = {"updated_at": b.get("updated_at"), "items_count": b.get("items_count"),
          "lastActivityAt": last}
    if stored is None or "updated_at" not in stored:
        emit(e, "never", fingerprint=fp, stored=stored)
        continue
    moved = [k for k in FIELDS if k not in stored or stored[k] != fp[k]]
    emit(e, "changed" if moved else "unchanged", fingerprint=fp, stored=stored, delta=moved)
PY
