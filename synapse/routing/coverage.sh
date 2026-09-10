#!/usr/bin/env bash
# coverage.sh — does a brain's map actually reach the router?
#
# Routing runs on the `kinds:` each domain declares, matched against intents.json. A kind that
# appears in no intent, or a domain no intent reaches, makes that content invisible — silently,
# and with no worse symptom than a confidently wrong answer sourced from somewhere else. That
# class of bug has been found by hand three times by three people. This is the join that finds
# it by asking: no LLM, no network, two files.
#
# WHY IT LIVES IN SYNAPSE AND NOT IN THE BRAIN (/drift, /sync-health)
#   The join needs intents.json, and DESIGN §12 forbids vendoring the intent table into a brain
#   ("Never vendor it into a brain"). A brain-local copy updates only by /upgrade PR, so a check
#   there starts false-alarming the moment the plugin's vocabulary grows and the brain has not
#   upgraded. The reader always runs the current table.
#
# USAGE
#   coverage.sh [<manifest>]                 full report   (default: .brainforge/brain-manifest.json)
#   coverage.sh [<manifest>] --map           the session map's ⚠ lines only
#   coverage.sh [<manifest>] --narrow-paths  one domain path per line, for the map's line marker
#
# EXIT
#   1  orphan kinds or unreachable domains — content the router cannot reach. A defect.
#   0  clean, or narrow gates only. A narrow gate is a smell, not a defect: the shape may be
#      deliberate, so it is reported but never fails the run. --map always exits 0.
#
# Dependency-free (grep/sed/awk only) because the session hook calls it. Relies on two parsing
# contracts: intents.json's one-intent-per-line layout (routing/README.md) and gen-manifest.sh's
# output formatting. Break either and this goes quiet, which is the exact failure it exists to
# catch.
set -u

mode=report
manifest=""
for a in "$@"; do
  case "$a" in
    --map)          mode=map ;;
    --narrow-paths) mode=narrow ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *)         manifest="$a" ;;
  esac
done
[ -n "$manifest" ] || manifest=".brainforge/brain-manifest.json"
intents="$(dirname "$0")/intents.json"

if [ ! -r "$manifest" ]; then
  [ "$mode" = map ] || echo "coverage: no manifest at $manifest"
  exit 0
fi
if [ ! -r "$intents" ]; then
  [ "$mode" = map ] || echo "coverage: no intent table at $intents"
  exit 0
fi

awk -v mode="$mode" -v manifest="$manifest" '
function addintent(kind, intent,   cur) {
  vocab[kind] = 1
  cur = intentsOf[kind]
  if (cur == "")                                    intentsOf[kind] = intent
  else if (index("|" cur "|", "|" intent "|") == 0) intentsOf[kind] = cur "|" intent
}

# ---- pass 1: intents.json. One intent per line is a parsing contract. ----
FNR == NR {
  if ($0 !~ /^[[:space:]]*"/) next
  b1 = index($0, "["); b2 = index($0, "]")
  if (b1 == 0 || b2 == 0 || b2 < b1) next
  q1 = index($0, "\""); rest = substr($0, q1 + 1)
  q2 = index(rest, "\""); if (q2 == 0) next
  intent = substr(rest, 1, q2 - 1)
  blob = substr($0, b1 + 1, b2 - b1 - 1); gsub(/[" ]/, "", blob)
  allIntents[++ni] = intent; intentKinds[intent] = blob
  n = split(blob, a, ",")
  for (i = 1; i <= n; i++) if (a[i] != "") addintent(a[i], intent)
  next
}

# ---- pass 2: the manifest. Domain keys sit at 6-space indent, band last of the four. ----
/^      "path": /   { v = $0; sub(/^      "path": "/,   "", v); sub(/",$/, "", v); path  = v }
/^      "title": /  { v = $0; sub(/^      "title": "/,  "", v); sub(/",$/, "", v); title = v }
/^      "kinds": /  { v = $0; sub(/^      "kinds": \[/, "", v); sub(/\],$/, "", v)
                      gsub(/[" ]/, "", v);                      kinds = v }
/^      "tokens": / { v = $0; sub(/^      "tokens": /,  "", v); sub(/,$/,  "", v); toks  = v }
/^      "band": /   { v = $0; sub(/^      "band": "/,   "", v); sub(/",$/, "", v); band  = v
                      domain() }

function domain(   n, a, i, k, m, b, j, reach, nreach, routable) {
  ndom++
  reach = ""; nreach = 0; routable = 0
  n = split(kinds, a, ",")
  for (i = 1; i <= n; i++) {
    k = a[i]; if (k == "") continue
    declared[k] = 1
    if (!(k in vocab)) {
      orphanKind[++norphan] = k; orphanPath[norphan] = path
      continue
    }
    routable++
    m = split(intentsOf[k], b, "|")
    for (j = 1; j <= m; j++)
      if (index("|" reach "|", "|" b[j] "|") == 0) {
        reach = (reach == "" ? b[j] : reach "|" b[j]); nreach++
      }
  }
  if (routable == 0) {
    unreachPath[++nunreach] = path
    unreachTitle[nunreach]  = title
    unreachKinds[nunreach]  = (kinds == "" ? "(declares none)" : kinds)
  }
  # The shape this exists for: a large domain the band gate opens for exactly one phrasing and
  # no other, so it stays unread while holding the only accurate doc on its subject.
  if (band == "expensive" && nreach == 1) {
    narrowPath[++nnarrow] = path; narrowIntent[nnarrow] = reach; narrowToks[nnarrow] = toks
  }
  path = ""; title = ""; kinds = ""; band = ""; toks = ""
}

END {
  if (mode == "narrow") {
    for (i = 1; i <= nnarrow; i++) print narrowPath[i]
    exit 0
  }

  # A map with no domains at all is the loudest possible defect and used to read as a pass,
  # because every "no findings" test is vacuously true on an empty set. It is also the second
  # check that should have caught a generator pointed at the wrong context root.
  if (ndom == 0) {
    if (mode == "map")
      print "   ⚠ this brain'"'"'s map lists NO domains — the generator found no _index.md under its context root."
    else {
      printf "Routing coverage — %s\n\n", manifest
      print "✗ the map lists no domains at all"
      print "    Nothing here is reachable, because there is nothing here. Either the brain has"
      print "    no _index.md files yet, or the generator ran against the wrong context root."
      print "    Check `contextRoot` in the manifest, then re-run: bash .brainforge/gen-manifest.sh"
    }
    # --map ALWAYS exits 0: the session hook must never fail, whatever it finds.
    exit (mode == "map") ? 0 : 1
  }

  if (mode == "map") {
    for (i = 1; i <= norphan; i++)
      printf "   ⚠ unroutable kind \"%s\" (%s) — no intent points at it; this content never routes.\n", \
             orphanKind[i], orphanPath[i]
    # Narrow gates are NOT warned about here. 21 of the 24 kinds appear in exactly one intent
    # and every shipped adapter mandates a single-intent kind, so a ⚠ per expensive
    # adapter-emitted domain would be permanent — the same disease as a staleness warning that
    # can never turn off. The map marks the domain line instead (--narrow-paths), which costs
    # ~3 tokens, carries the same signal to the reader, and implies no defect.
    exit 0
  }

  printf "Routing coverage — %s\n", manifest
  printf "  %d domains · %d intents · %d kinds in the routable vocabulary\n\n", ndom, ni, length(vocab)

  if (norphan) {
    print "✗ unroutable kinds — declared by a domain, pointed at by no intent"
    for (i = 1; i <= norphan; i++) printf "    %-24s %s\n", orphanKind[i], orphanPath[i]
    print ""
  }
  if (nunreach) {
    print "✗ unreachable domains — no declared kind any intent points at"
    for (i = 1; i <= nunreach; i++) printf "    %-34s %s\n", unreachPath[i], unreachKinds[i]
    print ""
  }
  if (nnarrow) {
    print "⚠ narrow gates — expensive domain behind a single intent"
    for (i = 1; i <= nnarrow; i++)
      printf "    %-34s %s tokens · only \"%s\"\n", narrowPath[i], narrowToks[i], narrowIntent[i]
    print ""
  }

  for (i = 1; i <= ni; i++) {
    n = split(intentKinds[allIntents[i]], a, ",")
    hit = 0
    for (j = 1; j <= n; j++) if (a[j] in declared) hit = 1
    if (!hit) dead[++ndead] = allIntents[i]
  }
  if (ndead) {
    print "· intents this brain cannot answer — no domain declares their kinds"
    for (i = 1; i <= ndead; i++) printf "    %s\n", dead[i]
    print ""
  }

  if (!norphan && !nunreach && !nnarrow)
    print "✓ every domain is reachable by at least one intent, and every declared kind routes."
  else
    printf "%d unroutable kind(s), %d unreachable domain(s), %d narrow gate(s).\n", \
           norphan, nunreach, nnarrow

  exit (norphan || nunreach) ? 1 : 0
}
' "$intents" "$manifest"
