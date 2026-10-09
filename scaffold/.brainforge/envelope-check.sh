#!/usr/bin/env bash
# envelope-check.sh — golden rule 6, as arithmetic instead of prose.
#
# For each named source (or every enabled source when none are named) it checks every doc and
# the _index.md in the manifest domain that source writes to (its `into:`), plus the domain
# total. It checks the whole domain, not only this run's docs: a breach nobody accepted keeps
# showing, and the script cannot see which files this run emitted.
#
# Envelope per doc, most specific first:
#   1. the doc's `acceptedSize` entry on the sources.json entry (doc relative to `into:`)
#   2. the row in pipeline/adapters/<adapter>.md § "0a. Size envelope"
#      (sources key -> adapter: repos -> github, websites -> website, any other key is its name)
#   3. 8,000
# Table grammar: first cell a backticked filename (exact row), a backticked `<placeholder>.md`
# or `per-page file` (wildcard row), or `domain total` / `per-domain total`; second cell `≤ N`.
# Bold is stripped; text after the closing backtick or after N is ignored. Exact beats wildcard.
# A table that does not parse, or a built-in adapter (figma, github, website, monday, ga) whose
# playbook file is missing, is reported, then the 8,000 default is used. A custom adapter with no
# playbook file gets the default silently.
#
# Flags a doc over its envelope, or one that grew >= 3x since <prev-manifest> (accepted docs
# too). No baseline (no prev, doc absent from it, or an _index.md in a prev older than schema 2)
# prints `was n/a`. With no domain-total row the domain check is skipped.
#
# USAGE
#   envelope-check.sh <prev-manifest> <manifest> <sources.json> [source-id...]
#   Run from the brain root (adapter tables are read from ./pipeline/adapters). <prev-manifest>
#   may be missing or empty (first sync).
#
# OUTPUT  one `⚠ rule-6:` line per breach, for the sync PR body verbatim. Nothing when clean.
# EXIT    0 checked (breaches or not); 1 bad arguments, unknown id, unreadable manifest or
#         sources.json, or no python3.
set -u

case "${1:-}" in -h|--help) sed -n '2,32p' "$0"; exit 0 ;; esac

if [ "$#" -lt 3 ]; then
  echo "✗ envelope-check: usage: envelope-check.sh <prev-manifest> <manifest> <sources.json> [source-id...]" >&2
  exit 1
fi
if ! command -v python3 > /dev/null 2>&1; then
  echo "✗ envelope-check: python3 not found, so golden rule 6 was not checked." >&2
  exit 1
fi

root_dir="$PWD"

python3 - "$root_dir/pipeline/adapters" "$@" <<'PY'
import json, os, re, sys

adapters_dir, prev_path, man_path, src_path = sys.argv[1:5]
ids = sys.argv[5:]
DEFAULT = 8000

def die(msg):
    sys.stderr.write("✗ envelope-check: " + msg + "\n")
    sys.exit(1)

def load(path, what):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        die("cannot read %s %s (%s)" % (what, path, e))

manifest = load(man_path, "manifest")
sources = load(src_path, "sources.json")
if not isinstance(manifest, dict) or not isinstance(manifest.get("domains"), list):
    die("manifest %s has no domains list" % man_path)

prev = None
if os.path.isfile(prev_path) and os.path.getsize(prev_path) > 0:
    prev = load(prev_path, "previous manifest")

def norm(p):
    p = (p or "").strip()
    while p.startswith("./"):
        p = p[2:]
    return p.strip("/")

def domains_of(m):
    out = {}
    if isinstance(m, dict):
        for d in m.get("domains") or []:
            if isinstance(d, dict):
                out[norm(d.get("path"))] = d
    return out

cur_domains = domains_of(manifest)
prev_domains = domains_of(prev)
prev_schema = prev.get("schema", 1) if isinstance(prev, dict) else 0

# --- select entries ---
entries = []  # (key, entry)
for key, val in sources.items():
    if key.startswith("$") or not isinstance(val, list):
        continue
    for e in val:
        if isinstance(e, dict):
            entries.append((key, e))
if ids:
    chosen = []
    for i in ids:
        hit = [(k, e) for k, e in entries if e.get("id") == i]
        if not hit:
            die("no source with id %r in %s" % (i, src_path))
        chosen.extend(hit)
else:
    chosen = [(k, e) for k, e in entries if e.get("enabled", True) is not False]

# --- adapter tables ---
ADAPTER = {"repos": "github", "websites": "website"}
BUILTIN = {"figma", "github", "website", "monday", "ga"}
tables = {}  # adapter -> (rows or None, unreadable bool)

def parse_table(adapter):
    path = os.path.join(adapters_dir, adapter + ".md")
    try:
        with open(path) as f:
            lines = f.read().splitlines()
    except Exception:
        return None, adapter in BUILTIN   # a shipped adapter's table must be there
    rows, in_sec = [], False
    for ln in lines:
        if re.match(r"^#+\s", ln):
            if in_sec:
                break
            in_sec = bool(re.match(r"^#+\s+0a\.\s+Size envelope", ln))
            continue
        if in_sec and ln.lstrip().startswith("|"):
            rows.append(ln)
    if not in_sec and not rows:
        return None, False          # no 0a section: the table MAY be omitted
    data = [r for r in rows[1:] if not re.match(r"^\s*\|[\s|:-]*\|\s*$", r)]
    if not data:
        return None, True
    parsed = {"exact": {}, "wild": None, "total": None}
    for r in data:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if len(cells) < 2:
            return None, True
        first = cells[0].replace("**", "").strip()
        second = cells[1].replace("**", "").strip()
        m = re.match(r"^≤\s*(\d{1,3}(?:,\d{3})+|\d+)(?!\d)", second)
        if not m:
            return None, True
        n = int(m.group(1).replace(",", ""))
        low = first.lower()
        if low in ("domain total", "per-domain total"):
            parsed["total"] = n
        elif low == "per-page file" or re.match(r"^`<[^`>]+>\.md`", first):
            parsed["wild"] = n
        else:
            fm = re.match(r"^`([^`<>]+)`", first)
            if not fm:
                return None, True
            parsed["exact"][fm.group(1)] = n
    return parsed, False

def table_for(key):
    adapter = ADAPTER.get(key, key)
    if adapter not in tables:
        tables[adapter] = parse_table(adapter)
    return adapter, tables[adapter]

out = []
def emit(line):
    if line not in out:
        out.append(line)

for key, e in chosen:
    into = norm(e.get("into"))
    if not into:
        continue
    adapter, (table, unreadable) = table_for(key)
    if unreadable:
        emit("⚠ rule-6: %s envelope table unreadable — used the 8,000 default" % adapter)
    dom = cur_domains.get(into)
    if dom is None:
        continue
    accepted = {}
    for a in e.get("acceptedSize") or []:
        if isinstance(a, dict) and isinstance(a.get("tokens"), int):
            accepted[norm(a.get("doc"))] = a["tokens"]
    pdom = prev_domains.get(into)
    pfiles = {}
    if pdom:
        for f in pdom.get("files") or []:
            if isinstance(f, dict) and isinstance(f.get("tokens"), int):
                pfiles[f.get("path")] = f["tokens"]

    docs = []  # (name, tokens, prev or None)
    if isinstance(dom.get("indexTokens"), int):
        p = None
        if pdom and prev_schema >= 2 and isinstance(pdom.get("indexTokens"), int):
            p = pdom["indexTokens"]
        docs.append(("_index.md", dom["indexTokens"], p))
    for f in dom.get("files") or []:
        if isinstance(f, dict) and isinstance(f.get("tokens"), int):
            docs.append((f.get("path"), f["tokens"], pfiles.get(f.get("path"))))

    for name, n, p in docs:
        if name in accepted:
            env = accepted[name]
        elif table and name in table["exact"]:
            env = table["exact"][name]
        elif table and table["wild"] is not None:
            env = table["wild"]
        else:
            env = DEFAULT
        over = n > env
        grew = p is not None and p > 0 and n >= 3 * p
        if over or grew:
            emit("⚠ rule-6: %s/%s is %d tokens (envelope %d / was %s) — consider aggregating."
                 % (into, name, n, env, "n/a" if p is None else str(p)))

    if table and table["total"] is not None and isinstance(dom.get("tokens"), int):
        if dom["tokens"] > table["total"]:
            emit("⚠ rule-6: %s totals %d tokens (envelope %d) — consider aggregating."
                 % (into, dom["tokens"], table["total"]))

for line in out:
    print(line)
PY
