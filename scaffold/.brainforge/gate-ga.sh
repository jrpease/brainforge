#!/usr/bin/env bash
# gate-ga.sh — the GA adapter's cheap change gate (pipeline/adapters/ga.md §1), as a script.
#
# Runs the tiny `sessions`-by-`date` report over the trailing window
# [lastSyncedThrough − lookbackDays, "yesterday"] and compares it with the stored slot.
# The end date is the literal string "yesterday", so the API resolves it in the property's
# reporting time zone; this script never reads the local clock.
#
# USAGE (from the brain root)
#   bash .brainforge/gate-ga.sh [<source-id>…]
#   With ids, gates those `ga` entries of sources.json; with none, every enabled `ga` entry.
#
# READS  sources.json (ga[]), .sync-state.json (ga[<propertyId>]), .env (^GOOGLE_APPLICATION_CREDENTIALS=,
#        matched, never sourced). Writes nothing: the state write stays in ga.md §3.
#
# CREDENTIALS, in order
#   1. GOOGLE_APPLICATION_CREDENTIALS in .env → exported, then
#      `gcloud auth application-default print-access-token`;
#   2. otherwise the same command against the owner's own-OAuth-client ADC;
#   3. no gcloud, or the command fails → not-checked (no credentials).
#
# OUTPUT  one JSON object per gated entry, one per line (JSON Lines), exit 0:
#   {"type":"ga","id":…,"status":"unchanged|changed|never|not-checked","reason":…,
#    "fingerprint":{"lastSyncedThrough":"YYYY-MM-DD","trailingSessionHashes":{"YYYYMMDD":n,…}},
#    "stored":{…},"delta":["YYYY-MM-DD",…]}
#   `delta` is the dates that are new (> lastSyncedThrough) or whose sessions differ from stored.
#   No stored slot → never, with no call. `fingerprint` is in the shape ga.md §3 stores.
#
# EXIT  1 only for misuse (no sources.json, an unknown id) or no python3, message on stderr.
set -u

case "${1:-}" in -h|--help) sed -n '2,29p' "$0"; exit 0 ;; esac

if ! command -v python3 > /dev/null 2>&1; then
  echo "gate-ga: python3 not found" >&2
  exit 1
fi

python3 - "$@" <<'PY'
import datetime, json, os, re, shutil, subprocess, sys, tempfile

ids = sys.argv[1:]

def die(msg):
    sys.stderr.write("gate-ga: " + msg + "\n")
    sys.exit(1)

try:
    with open("sources.json") as f:
        sources = json.load(f)
except FileNotFoundError:
    die("no sources.json at the brain root")
except Exception as e:
    die(f"sources.json does not parse ({e})")

entries = [e for e in (sources.get("ga") or []) if isinstance(e, dict)]
if ids:
    byid = {e.get("id"): e for e in entries}
    for i in ids:
        if i not in byid:
            die(f"unknown ga source id: {i}")
    entries = [byid[i] for i in ids]
else:
    entries = [e for e in entries if e.get("enabled", True) is not False]

try:
    with open(".sync-state.json") as f:
        state = (json.load(f).get("ga") or {})
except Exception:
    state = {}

def env_value(key):
    try:
        with open(".env") as f:
            for line in f:
                m = re.match(r"^" + re.escape(key) + r"=(.*)$", line.rstrip("\n"))
                if m:
                    v = m.group(1).strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                        v = v[1:-1]
                    return v
    except FileNotFoundError:
        pass
    return None

_token = []
def token():
    if not _token:
        tok = None
        if shutil.which("gcloud"):
            env = dict(os.environ)
            gac = env_value("GOOGLE_APPLICATION_CREDENTIALS")
            if gac:
                env["GOOGLE_APPLICATION_CREDENTIALS"] = gac
            try:
                r = subprocess.run(["gcloud", "auth", "application-default", "print-access-token"],
                                   env=env, capture_output=True, text=True)
                if r.returncode == 0 and r.stdout.strip():
                    tok = r.stdout.strip().splitlines()[-1].strip()
            except OSError:
                tok = None
        _token.append(tok)
    return _token[0]

def emit(e, status, reason=None, fingerprint=None, stored=None, delta=None):
    print(json.dumps({"type": "ga", "id": e.get("id"), "status": status, "reason": reason,
                      "fingerprint": fingerprint, "stored": stored, "delta": delta or []}))

def iso(d):  # YYYYMMDD -> YYYY-MM-DD
    return f"{d[0:4]}-{d[4:6]}-{d[6:8]}"

for e in entries:
    pid = str(e.get("propertyId", ""))
    slot = state.get(pid)
    if not isinstance(slot, dict) or not slot.get("lastSyncedThrough"):
        emit(e, "never", stored=slot if isinstance(slot, dict) else None)
        continue
    last = slot["lastSyncedThrough"]
    stored_hashes = slot.get("trailingSessionHashes") or {}
    lookback = int(e.get("lookbackDays", 3))
    try:
        start = datetime.date.fromisoformat(last) - datetime.timedelta(days=lookback)
    except ValueError:
        emit(e, "not-checked", f"stored lastSyncedThrough unreadable: {last}", stored=slot)
        continue

    tok = token()
    if not tok:
        emit(e, "not-checked", "no credentials", stored=slot)
        continue

    body = json.dumps({"dateRanges": [{"startDate": start.isoformat(), "endDate": "yesterday"}],
                       "dimensions": [{"name": "date"}], "metrics": [{"name": "sessions"}],
                       "orderBys": [{"dimension": {"dimensionName": "date"}}]},
                      separators=(",", ":"))
    url = f"https://analyticsdata.googleapis.com/v1beta/properties/{pid}:runReport"
    with tempfile.NamedTemporaryFile() as out:
        try:
            r = subprocess.run(["curl", "-s", "--max-time", "30", "-X", "POST",
                                "-H", f"Authorization: Bearer {tok}",
                                "-H", "Content-Type: application/json",
                                "-d", body, "-o", out.name, "-w", "%{http_code}", url],
                               capture_output=True, text=True)
        except OSError:
            emit(e, "not-checked", "offline", stored=slot)
            continue
        if r.returncode != 0:
            emit(e, "not-checked", "offline", stored=slot)
            continue
        code = r.stdout.strip()
        if code != "200":
            emit(e, "not-checked", f"HTTP {code}", stored=slot)
            continue
        try:
            resp = json.load(open(out.name))
            rows = {row["dimensionValues"][0]["value"]: int(row["metricValues"][0]["value"])
                    for row in (resp.get("rows") or [])}
        except Exception:
            emit(e, "not-checked", "unreadable response", stored=slot)
            continue

    last_key = last.replace("-", "")
    start_key = start.isoformat().replace("-", "")
    changed = set(d for d in rows if d > last_key)                      # new days
    for d, n in stored_hashes.items():                                  # restated days
        if d >= start_key and int(rows.get(d, 0)) != int(n):
            changed.add(d)
    dates = sorted(rows)
    fingerprint = {
        "lastSyncedThrough": iso(dates[-1]) if dates else last,
        "trailingSessionHashes": {d: rows[d] for d in dates[-lookback:]} if lookback > 0 else {},
    }
    emit(e, "changed" if changed else "unchanged", fingerprint=fingerprint, stored=slot,
         delta=[iso(d) for d in sorted(changed)])
PY
