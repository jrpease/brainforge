#!/usr/bin/env bash
# gate-website.sh — the website adapter's §1 cheap change gate, as a script.
#
# USAGE   bash .brainforge/gate-website.sh [<source-id>...]    (run from the brain root)
#         bash .brainforge/gate-website.sh --fingerprint <source-id>
#         With ids it gates those websites[] entries; with none, every enabled one.
#         --fingerprint downloads every sitemap URL of one entry and prints its full
#         fingerprint (status `fingerprint`, empty delta): §2 runs it first on a `never` source.
# OUTPUT  one JSON object per entry, one per line (JSON Lines), exit 0:
#           {"type","id","status","reason","fingerprint","stored","delta"}
#         status: unchanged | changed | never | not-checked  (website never emits `blocked`),
#         plus `fingerprint`, only from --fingerprint.
#         fingerprint {"urls": {<url>: {"lastmod","etag","sha256"}}} is the shape §3 stores
#         verbatim under .sync-state.json websites[<id>].urls. `sha256` is the page body's hash:
#         the content, which is what "changed" means. An ETag only stands in for it, and a CDN
#         serving identical bytes from two origins gives one page two ETags. So a 200 whose body
#         hashes to the stored value is unchanged, and so is a changed <lastmod> over identical
#         bytes. Every page the gate decides on, it downloads: a delta URL's etag and hash come
#         from that download, null only when the download failed or was not 2xx. Redirects are
#         followed (up to 10): a page is measured at the URL it resolves to.
# EXIT    1 only for misuse (unknown id, or no sources.json), message on stderr.
# Read-only: never writes .sync-state.json. No credentials. A caller that gets no JSON treats
# the source as `not-checked (gate failed)`, never as unchanged.
set -u
command -v python3 >/dev/null 2>&1 || { echo "gate-website: python3 not found" >&2; exit 1; }
exec python3 - "$@" <<'PY'
import datetime, email.utils, hashlib, json, os, re, subprocess, sys, tempfile

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
full = bool(ids) and ids[0] == "--fingerprint"
if full:
    ids = ids[1:]
    if len(ids) != 1:
        die("--fingerprint takes exactly one source id")
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
    """Returns (status, body bytes, header_text). Raises Offline when curl cannot connect."""
    bf = tempfile.NamedTemporaryFile(delete=False); bf.close()
    hf = tempfile.NamedTemporaryFile(delete=False); hf.close()
    try:
        # -L: a trailing-slash or http->https redirect is followed to the page it names; the
        # status and body are the final hop's, and so is the etag (see download)
        p = subprocess.run(["curl", "-sS", "-L", "--max-redirs", "10", "--max-time", "30",
                            "-o", bf.name, "-D", hf.name, "-w", "%{http_code}"] + args,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode != 0:
            raise Offline()
        status = p.stdout.decode().strip()
        return status, open(bf.name, "rb").read(), open(hf.name, errors="replace").read()
    except OSError:
        raise Offline()
    finally:
        os.unlink(bf.name); os.unlink(hf.name)

def download(loc, hdrs=()):
    """(status, etag, sha256) for one page; None when curl fails for it. One slow or broken
    page never fails the whole site: the caller lists it in the delta with null validators."""
    try:
        st, body, hdr = curl(list(hdrs) + [loc])
    except Offline:
        return None
    final = re.split(r"^HTTP/", hdr, flags=re.M)[-1]  # -D holds every redirect hop's headers
    m = re.search(r"^etag:\s*(.+?)\s*$", final, re.I | re.M)
    etag = m.group(1) if m else None
    return st, etag, (hashlib.sha256(body).hexdigest() if st.startswith("2") else None)

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
    if not stored and not full:
        return emit(e, "never")
    sitemap = e.get("sitemap") or (e.get("url", "").rstrip("/") + "/sitemap.xml")
    try:
        status, body, _ = curl([sitemap])
        if not status.startswith("2"):
            return emit(e, "not-checked", "HTTP %s" % status, stored=stored)
        urls = parse_sitemap(body.decode("utf-8", errors="replace"))
        if full:
            fp = {}
            for loc, lastmod in urls:
                got = download(loc)
                ok = got is not None and got[0].startswith("2")
                fp[loc] = {"lastmod": lastmod, "etag": got[1] if ok else None, "sha256": got[2] if ok else None}
            return emit(e, "fingerprint", fp={"urls": fp}, stored=stored)
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
                got = download(loc, hdrs)
                if got is not None and got[0] == "304":
                    fp[loc] = {"lastmod": prev.get("lastmod") if lastmod is None else lastmod,
                               "etag": got[1] or prev.get("etag"), "sha256": prev.get("sha256")}
                    continue
            else:
                got = download(loc)  # a new URL, or a changed <lastmod>: the body decides
            ok = got is not None and got[0].startswith("2")
            if ok and prev is not None and prev.get("sha256") and prev["sha256"] == got[2]:
                # identical bytes: another origin's ETag, or a <lastmod> bumped by a rebuild
                fp[loc] = {"lastmod": prev.get("lastmod") if lastmod is None else lastmod,
                           "etag": got[1] or prev.get("etag"), "sha256": got[2]}
                continue
            delta.append(loc)
            fp[loc] = {"lastmod": lastmod, "etag": got[1] if ok else None, "sha256": got[2] if ok else None}
        emit(e, "changed" if delta else "unchanged", fp={"urls": fp}, stored=stored, delta=delta)
    except Offline:
        emit(e, "not-checked", "offline", stored=stored)

for e in chosen:
    gate(e)
PY
