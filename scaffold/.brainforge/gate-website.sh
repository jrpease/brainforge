#!/usr/bin/env bash
# gate-website.sh — the website adapter's §1 cheap change gate, as a script.
#
# USAGE   bash .brainforge/gate-website.sh [<source-id>...]    (run from the brain root)
#         With ids it gates those websites[] entries; with none, every enabled one.
# OUTPUT  one JSON object per entry, one per line (JSON Lines), exit 0:
#           {"type","id","status","reason","fingerprint","stored","delta"}
#         status: unchanged | changed | never | not-checked  (website never emits `blocked`)
#         fingerprint {"urls": {<url>: {"lastmod","etag"}}} is the shape §3 stores under
#         .sync-state.json websites[<id>].urls. Skipped URLs carry the stored etag (or the one
#         the 304 returned); `delta` URLs carry the new <lastmod> and etag null, because the
#         gate never fetches the page. §3 sets the etag of each URL §2 fetched from that response.
# EXIT    1 only for misuse (unknown id, or no sources.json), message on stderr.
# Read-only: never writes .sync-state.json. No credentials. A caller that gets no JSON treats
# the source as `not-checked (gate failed)`, never as unchanged.
set -u
command -v python3 >/dev/null 2>&1 || { echo "gate-website: python3 not found" >&2; exit 1; }
exec python3 - "$@" <<'PY'
import datetime, email.utils, json, os, re, subprocess, sys, tempfile

def die(msg):
    sys.stderr.write("gate-website: %s\n" % msg)
    sys.exit(1)

if not os.path.isfile("sources.json"):
    die("no sources.json in the current directory (run from the brain root)")
try:
    sources = json.load(open("sources.json"))
except Exception as e:
    die("sources.json unreadable: %s" % e)
try:
    state = json.load(open(".sync-state.json")) if os.path.isfile(".sync-state.json") else {}
except Exception:
    state = {}

entries = sources.get("websites") or []
ids = sys.argv[1:]
if ids:
    byid = {e.get("id"): e for e in entries}
    for i in ids:
        if i not in byid:
            die("unknown website id: %s" % i)
    chosen = [byid[i] for i in ids]
else:
    chosen = [e for e in entries if e.get("enabled", True) is not False]

class Offline(Exception): pass

def curl(args):
    """Returns (status, body, header_text). Raises Offline when curl cannot connect."""
    bf = tempfile.NamedTemporaryFile(delete=False); bf.close()
    hf = tempfile.NamedTemporaryFile(delete=False); hf.close()
    try:
        p = subprocess.run(["curl", "-sS", "--max-time", "30", "-o", bf.name, "-D", hf.name,
                            "-w", "%{http_code}"] + args,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode != 0:
            raise Offline()
        status = p.stdout.decode().strip()
        return status, open(bf.name, errors="replace").read(), open(hf.name, errors="replace").read()
    except OSError:
        raise Offline()
    finally:
        os.unlink(bf.name); os.unlink(hf.name)

def parse_sitemap(xml):
    out = []
    for blk in re.findall(r"<url>(.*?)</url>", xml, re.S):
        loc = re.search(r"<loc>\s*(.*?)\s*</loc>", blk, re.S)
        if not loc:
            continue
        lm = re.search(r"<lastmod>\s*(.*?)\s*</lastmod>", blk, re.S)
        out.append((loc.group(1), lm.group(1) if lm else None))
    return out

def http_date(lastmod):
    """A sitemap <lastmod> (W3C date) as an HTTP-date, or None when it does not parse.
    A server must ignore an If-Modified-Since that is not a valid HTTP-date (RFC 7232 3.3)."""
    v = lastmod.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(v)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return email.utils.format_datetime(dt.astimezone(datetime.timezone.utc), usegmt=True)

def emit(e, status, reason=None, fp=None, stored=None, delta=None):
    print(json.dumps({"type": "website", "id": e.get("id"), "status": status, "reason": reason,
                      "fingerprint": fp, "stored": stored, "delta": delta if delta is not None else []}))

def gate(e):
    slot = (state.get("websites") or {}).get(e.get("id")) or {}
    stored = slot.get("urls") if isinstance(slot, dict) else None
    if not stored:
        return emit(e, "never")
    sitemap = e.get("sitemap") or (e.get("url", "").rstrip("/") + "/sitemap.xml")
    try:
        status, body, _ = curl([sitemap])
        if not status.startswith("2"):
            return emit(e, "not-checked", "HTTP %s" % status, stored=stored)
        urls = parse_sitemap(body)
        fp, delta = {}, []
        for loc, lastmod in urls:
            prev = stored.get(loc)
            if prev is not None and (lastmod is None or prev.get("lastmod") == lastmod):
                # lastmod equal (or absent): ask the server, with the stored validators
                hdrs = []
                if prev.get("etag"):
                    hdrs += ["-H", "If-None-Match: %s" % prev["etag"]]
                ims = http_date(prev["lastmod"]) if prev.get("lastmod") else None
                if ims:
                    hdrs += ["-H", "If-Modified-Since: %s" % ims]
                st, _, hdr = curl(hdrs + [loc])
                if st == "304":
                    m = re.search(r"^etag:\s*(.+?)\s*$", hdr, re.I | re.M)
                    fp[loc] = {"lastmod": prev.get("lastmod") if lastmod is None else lastmod,
                               "etag": m.group(1) if m else prev.get("etag")}
                    continue
            delta.append(loc)
            fp[loc] = {"lastmod": lastmod, "etag": None}
        emit(e, "changed" if delta else "unchanged", fp={"urls": fp}, stored=stored, delta=delta)
    except Offline:
        emit(e, "not-checked", "offline", stored=stored)

for e in chosen:
    gate(e)
PY
