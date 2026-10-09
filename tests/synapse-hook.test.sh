#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/synapse/hooks/session-start.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# fixture brain repo with a committed manifest
BRAIN="$TMP/origin/acme-brain"; mkdir -p "$BRAIN"; cd "$BRAIN"
git init -q
mkdir -p context/canon/brand .brainforge
cat > context/canon/brand/_index.md <<'EOF'
---
kinds: [brand-voice]
title: Brand
---
EOF
printf '# Voice\nsome words here\n' > context/canon/brand/voice.md
git add -A; git commit -q -m brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh"
git add -A; git commit -q -m manifest

# no SYNAPSE_BRAINS -> silent no-op
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="" bash "$HOOK")
[ -z "$out" ] || fail "should be silent with no subscriptions"

# subscribed -> clones and renders map
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$BRAIN" bash "$HOOK")
[ -d "$TMP/home/acme-brain/.git" ]            || fail "brain not cloned"
echo "$out" | grep -q "acme-brain"             || fail "map missing brain name"
echo "$out" | grep -q "Brand"                  || fail "map missing domain title"
echo "$out" | grep -q "brand-voice"            || fail "map missing kinds"
echo "$out" | grep -q "cheap"                  || fail "map missing band"
echo "$out" | grep -qi "canon"                 || fail "map missing canon/derived rule"
# brand-voice IS in the vocabulary -> a healthy brain must draw no unroutable warning
echo "$out" | grep -q "unroutable"             && fail "false unroutable warning on an in-vocabulary kind"

# second run -> pull path, still renders
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$BRAIN" bash "$HOOK")
echo "$out" | grep -q "acme-brain"             || fail "map missing on re-run"

# --- staleness, measured by content (docs/specs/2026-09-09-audit-hardening.md, Finding 1) ---
# THE regression. A healthy brain whose map was generated seconds ago must draw NO warning.
# The old check compared generatedFrom against HEAD, and the commit that lands the manifest
# always moves HEAD -- so it fired on every healthy brain, forever, and readers learned to
# scroll past it. Nothing asserted its absence, which is how it shipped.
echo "$out" | grep -qi "predates"              && fail "false staleness warning on a freshly generated map"
echo "$out" | grep -q  "narrow gate"           && fail "cheap domain wrongly flagged as a narrow gate"

# content genuinely changed since the map was generated -> the warning must fire
cd "$BRAIN"
printf '# Voice\nsome words here, and rather more of them now\n' > context/canon/brand/voice.md
git add -A; git commit -q -m "edit canon without regenerating"
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$BRAIN" bash "$HOOK")
echo "$out" | grep -q "predates the current content" || fail "real staleness not announced"

# regenerate -> it must clear
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh" > /dev/null
git add -A; git commit -q -m "regenerate the map"
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$BRAIN" bash "$HOOK")
echo "$out" | grep -qi "predates"              && fail "staleness warning did not clear after regeneration"

# a pre-schema-3 brain cannot be checked at all, and must say so with the fix, not stay quiet
sed -i.bak 's/"schema": 3/"schema": 2/; /"contextFingerprint"/d; /"contextRoot"/d' \
  .brainforge/brain-manifest.json && rm -f .brainforge/brain-manifest.json.bak
git add -A; git commit -q -m "simulate a brain that has not upgraded"
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$BRAIN" bash "$HOOK")
echo "$out" | grep -q "pre-schema-3"           || fail "old manifest must say staleness is uncheckable"
echo "$out" | grep -q "gen-manifest.sh"        || fail "the pre-schema-3 line must name the command that fixes it"
# put it back so later cases start from a healthy brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh" > /dev/null
git add -A; git commit -q -m "restore the map"

# bad remote -> loud ungrounded line, exit 0
out=$(SYNAPSE_HOME="$TMP/home" SYNAPSE_BRAINS="$TMP/nope" bash "$HOOK") || fail "hook must not hard-fail"
echo "$out" | grep -qi "UNGROUNDED"            || fail "missing-brain must announce ungrounded"

# collision: two different remotes share basename "acme-brain" -> must never alias
BRAIN2="$TMP/other-org/acme-brain"; mkdir -p "$BRAIN2"; cd "$BRAIN2"
git init -q
mkdir -p context/canon/legal .brainforge
cat > context/canon/legal/_index.md <<'EOF'
---
kinds: [legal]
title: Legal
---
EOF
printf '# Terms\nsome other words entirely\n' > context/canon/legal/terms.md
git add -A; git commit -q -m brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh"
git add -A; git commit -q -m manifest

out=$(SYNAPSE_HOME="$TMP/home2" SYNAPSE_BRAINS="$BRAIN,$BRAIN2" bash "$HOOK") || fail "hook must not hard-fail on collision"
echo "$out" | grep -qi "collision"             || fail "missing collision warning"
echo "$out" | grep -q "Brand"                  || fail "first brain's domain missing after collision"
echo "$out" | grep -q "Legal"                  || fail "second brain's domain missing after collision (aliased onto first)"

# "legal" is not in the vocabulary -> the domain routes to nothing and must say so.
# Without this the domain renders normally and fails silently, which is the whole bug.
echo "$out" | grep -q 'unroutable kind "legal"' || fail "unroutable kind not announced"
echo "$out" | grep -q "context/canon/legal"     || fail "unroutable warning must name the domain"

# Mixed domain: one kind routes, one does not. Warn per KIND, not per domain --
# the good kind must not be flagged, and the domain must still render normally.
BRAIN3="$TMP/third/mixed-brain"; mkdir -p "$BRAIN3"; cd "$BRAIN3"
git init -q
mkdir -p context/canon/mixed .brainforge
cat > context/canon/mixed/_index.md <<'EOF'
---
kinds: [brand-voice, wildly-invented]
title: Mixed
---
EOF
printf '# Doc\na few words here\n' > context/canon/mixed/doc.md
git add -A; git commit -q -m brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh"
git add -A; git commit -q -m manifest

out=$(SYNAPSE_HOME="$TMP/home3" SYNAPSE_BRAINS="$BRAIN3" bash "$HOOK") || fail "hook must not hard-fail on mixed kinds"
echo "$out" | grep -q "Mixed"                          || fail "mixed domain missing from map"
echo "$out" | grep -q 'unroutable kind "wildly-invented"' || fail "bad kind in a mixed domain not announced"
echo "$out" | grep -q 'unroutable kind "brand-voice"'  && fail "good kind in a mixed domain wrongly announced"

# Narrow gate: an expensive domain exactly one intent reaches. The band gate opens it on a
# direct match only, so one phrasing loads it and no other does -- the shape that hid a large
# expensive domain of a real brain, including the only accurate doc it had on the subject.
BRAIN4="$TMP/fourth/narrow-brain"; mkdir -p "$BRAIN4"; cd "$BRAIN4"
git init -q
mkdir -p context/derived/tracker .brainforge
cat > context/derived/tracker/_index.md <<'EOF'
---
kinds: [project-tracking]
title: Tracker
---
EOF
awk 'BEGIN { for (i=0;i<9000;i++) printf "word " }' > context/derived/tracker/big.md
git add -A; git commit -q -m brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh"
git add -A; git commit -q -m manifest

out=$(SYNAPSE_HOME="$TMP/home4" SYNAPSE_BRAINS="$BRAIN4" bash "$HOOK") || fail "hook must not hard-fail on a narrow gate"
echo "$out" | grep -q "expensive · single-intent"       || fail "single-intent marker missing from the domain line"
# It is a MARKER, not a warning. 21 of 24 kinds are single-intent and a synced domain usually
# carries one, so a ⚠ here would fire permanently on ordinary adapter output -- the same disease as a
# staleness warning that can never turn off.
echo "$out" | grep -q "narrow gate"                     && fail "narrow gate must not be its own map line"
echo "$out" | grep -q "⚠"                               && fail "a single-intent domain must draw no warning at all"
echo "$out" | grep -q 'unroutable kind "project-tracking"' && fail "in-vocabulary kind wrongly called unroutable"

# The BAND is what makes it narrow: the same single-intent kind in a cheap domain gets no marker.
BRAIN5="$TMP/fifth/cheap-brain"; mkdir -p "$BRAIN5"; cd "$BRAIN5"
git init -q
mkdir -p context/derived/tracker .brainforge
cat > context/derived/tracker/_index.md <<'EOF'
---
kinds: [project-tracking]
title: Tracker
---
EOF
printf '# Small
a few words only
' > context/derived/tracker/small.md
git add -A; git commit -q -m brain
bash "$ROOT/scaffold/.brainforge/gen-manifest.sh" > /dev/null
git add -A; git commit -q -m manifest
out=$(SYNAPSE_HOME="$TMP/home5" SYNAPSE_BRAINS="$BRAIN5" bash "$HOOK")
echo "$out" | grep -q "cheap"                           || fail "cheap fixture is not cheap"
echo "$out" | grep -q "single-intent"                   && fail "cheap domain wrongly marked single-intent"

echo "PASS synapse-hook"
