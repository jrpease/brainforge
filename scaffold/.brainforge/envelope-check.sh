#!/usr/bin/env bash
# envelope-check.sh — golden rule 6, as arithmetic instead of prose.
#
# For each named source (or every enabled source when none are named) it checks every doc and
# the _index.md in the manifest domain that source writes to (its `into:`), plus the domain
# total. It checks the whole domain, not only this run's docs: a breach nobody accepted keeps
# showing, and the script cannot see which files this run emitted.
#
# Envelope per doc, most specific first:
#   1. the doc's `acceptedSize` on any sources.json entry feeding the domain, enabled or not (doc
#      relative to `into:`)
#   2. the row in pipeline/adapters/<adapter>.md § "0a. Size envelope"
#      (sources key -> adapter: repos -> github, websites -> website, any other key is its name)
#   3. 8,000
# Table grammar: first cell a backticked filename (exact row), a backticked name with one or more
# `<placeholder>`s (wildcard row, a glob where each placeholder is `*`), `per-page file` (wildcard
# row matching any doc), or `domain total` / `per-domain total`; second cell `≤ N`.
# Bold is stripped; text after the closing backtick or after N is ignored. Exact beats wildcard,
# and among wildcard rows the one with the most literal characters wins.
# A table that does not parse, or a built-in adapter (figma, github, website, monday, ga) whose
# playbook file is missing, is reported, then the 8,000 default is used. A custom adapter with no
# playbook file gets the default silently.
#
# When several enabled adapters feed one domain, a doc is measured only against the adapter that emitted it,
# read from `generated-by:` then `source:` in its frontmatter. A doc naming none of them, and every
# shared _index.md, takes the most specific row across them (the largest on a tie). The domain total
# prints once, against the largest total they declare.
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

case "${1:-}" in -h|--help) sed -n '2,40p' "$0"; exit 0 ;; esac

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
    parsed = {"exact": {}, "wild": [], "total": None}
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
        elif low == "per-page file":
            parsed["wild"].append(("", re.compile(r".*", re.S), n))
        else:
            fm = re.match(r"^`([^`]+)`", first)
            if not fm:
                return None, True
            literals = re.split(r"<[^<>]+>", fm.group(1))
            if any("<" in part or ">" in part for part in literals):
                return None, True
            if len(literals) == 1:
                parsed["exact"][fm.group(1)] = n
            else:
                pattern = re.compile(".*".join(re.escape(part) for part in literals), re.S)
                parsed["wild"].append(("".join(literals), pattern, n))
    parsed["wild"].sort(key=lambda row: len(row[0]), reverse=True)   # stable: ties keep table order
    return parsed, False

def wildcard_envelope(table, name):
    for _literal, pattern, n in table["wild"]:
        if pattern.fullmatch(name):
            return n
    return None

def table_of(adapter):
    if adapter not in tables:
        tables[adapter] = parse_table(adapter)
    return tables[adapter]

# A domain can have several sources writing into it, and an acceptance is a decision about the doc
# or the domain, not about one entry: one on any entry feeding the domain (enabled or not, chosen or
# not) covers them all. Several for one doc: the latest `since` wins, ties go to the larger number.
# Tables are narrower: a disabled entry's adapter only counts when that entry was named, so a parked
# source sharing the folder can never raise a live domain's envelope.
chosen_entries = {id(_e) for _k, _e in chosen}
feeders = {}   # into -> adapters of the enabled or named entries feeding it, in sources.json order
accepts = {}   # (into, doc) -> (since, tokens); doc "domain total" is the domain's
for _k, _e in entries:
    _into = norm(_e.get("into"))
    if not _into:
        continue
    _adapter = ADAPTER.get(_k, _k)
    if _e.get("enabled", True) is not False or id(_e) in chosen_entries:
        if _adapter not in feeders.setdefault(_into, []):
            feeders[_into].append(_adapter)
    for a in _e.get("acceptedSize") or []:
        if isinstance(a, dict) and isinstance(a.get("tokens"), int):
            slot = (_into, norm(a.get("doc")))
            cand = (str(a.get("since") or ""), a["tokens"])
            if slot not in accepts or cand > accepts[slot]:
                accepts[slot] = cand

def frontmatter(path):
    found = {}
    try:
        with open(path, errors="replace") as f:
            if f.readline().strip() != "---":
                return found
            for ln in f:
                if ln.strip() == "---":
                    break
                m = re.match(r"^(generated-by|source):\s*(.*)$", ln)
                if m:
                    found[m.group(1)] = m.group(2).strip().strip("\"'")
    except OSError:
        pass
    return found

SOURCE_WORD = {"repo": "github", "repos": "github", "websites": "website"}

def emitters(into, name, feeding):
    """The adapters a doc is measured against. Nothing to decide with one feeder, and no feeder owns
    a shared _index.md. Otherwise generated-by, then source, and every feeder when neither names one."""
    if len(feeding) < 2 or name == "_index.md":
        return feeding
    fm = frontmatter(os.path.join(into, name))
    gen = fm.get("generated-by", "")
    named = re.findall(r"adapters/([\w-]+)\.md", gen) + re.findall(r"^([\w-]+)-adapter\b", gen)
    hit = [a for a in feeding if a in named]
    if hit:
        return hit
    word = re.match(r"[a-z0-9-]*", fm.get("source", "").lower()).group(0)
    word = SOURCE_WORD.get(word, word)
    return [word] if word in feeding else feeding

def envelope_for(name, adapters):
    """Exact row, then wildcard row, then the default; the largest when adapters tie on that."""
    best = (0, DEFAULT)
    for adapter in adapters:
        table = table_of(adapter)[0]
        if not table:
            continue
        if name in table["exact"]:
            best = max(best, (2, table["exact"][name]))
        else:
            wild = wildcard_envelope(table, name)
            if wild is not None:
                best = max(best, (1, wild))
    return best[1]

out = []
def emit(line):
    if line not in out:
        out.append(line)

checked = set()
for key, e in chosen:
    into = norm(e.get("into"))
    if not into:
        continue
    adapter = ADAPTER.get(key, key)
    if table_of(adapter)[1]:
        emit("⚠ rule-6: %s envelope table unreadable — used the 8,000 default" % adapter)
    dom = cur_domains.get(into)
    if dom is None or into in checked:
        continue
    checked.add(into)
    feeding = feeders[into]
    for other in feeding:
        if table_of(other)[1]:
            emit("⚠ rule-6: %s envelope table unreadable — used the 8,000 default" % other)
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
        if (into, name) in accepts:
            env = accepts[(into, name)][1]
        else:
            env = envelope_for(name, emitters(into, name, feeding))
        over = n > env
        grew = p is not None and p > 0 and n >= 3 * p
        if over or grew:
            emit("⚠ rule-6: %s/%s is %d tokens (envelope %d / was %s) — consider aggregating."
                 % (into, name, n, env, "n/a" if p is None else str(p)))

    # One line per domain: an accepted "domain total" replaces the tables' totals, and when several
    # feeding adapters declare one the largest applies.
    if (into, "domain total") in accepts:
        total = accepts[(into, "domain total")][1]
    else:
        totals = [table_of(a)[0]["total"] for a in feeding
                  if table_of(a)[0] and table_of(a)[0]["total"] is not None]
        total = max(totals) if totals else None
    if total is not None and isinstance(dom.get("tokens"), int):
        if dom["tokens"] > total:
            emit("⚠ rule-6: %s totals %d tokens (envelope %d) — consider aggregating."
                 % (into, dom["tokens"], total))

for line in out:
    print(line)
PY
