#!/usr/bin/env bash
# regen-if-stale.sh — regenerate the brain manifest only when the map is stale.
#
# Run from the brain root. The CI workflow (.github/workflows/brainforge-manifest.yml) calls it
# after every push to the default branch; it is also safe to run by hand.
#
# "Stale" is exactly the reader's test (synapse's session-start hook): the committed
# contextFingerprint differs from `git rev-parse HEAD:<contextRoot>`, or the map is missing or
# has no fingerprint. A current map is left byte-for-byte alone, so a push that changed nothing
# under the context root costs nothing and commits nothing (regenerating anyway would rewrite
# generatedAt and churn a commit every day).
#
# PRINTS  CURRENT                         nothing to do
#         REGENERATED <old|none> -> <new> the manifest was rewritten; commit it
# EXIT    0 on either; 1 when regeneration cannot produce a map the reader will accept (an
#         empty fingerprint, or one that still differs from HEAD). Never commits anything.
#
# Dependency-free (bash, git, sed), like gen-manifest.sh.
set -u

[ -f .brainforge/gen-manifest.sh ] || exit 0
m=.brainforge/brain-manifest.json

field() { # the reader's parse, per gen-manifest.sh's formatting contract
  [ -f "$m" ] && sed -n "s/^  \"$1\": \"\(.*\)\",\$/\1/p" "$m" | head -1
}
# same root precedence as gen-manifest.sh: the env var, else the manifest, else the default
root="${BRAIN_CONTEXT_DIR:-$(field contextRoot)}"
root="${root:-context}"
live=$(git rev-parse --verify -q "HEAD:$root" 2>/dev/null || true)
old=$(field contextFingerprint)

if [ -n "$old" ] && [ "$old" = "$live" ]; then
  echo "CURRENT"
  exit 0
fi

bash .brainforge/gen-manifest.sh >&2 || { echo "regen-if-stale: gen-manifest.sh failed" >&2; exit 1; }
new=$(field contextFingerprint)
if ! grep -q '^  "contextFingerprint": ' "$m" 2>/dev/null; then
  echo "regen-if-stale: this brain's gen-manifest.sh predates schema 3 and writes no fingerprint," \
       "so the reader can never check its map. Upgrade the runtime (/upgrade); if the generator" \
       "is flagged as locally modified, reconcile it to the shipped version first." >&2
  exit 1
fi
if [ -z "$new" ]; then
  echo "regen-if-stale: the context root '$root' is not a tree in HEAD (nothing committed under it," \
       "or the wrong root), so the map has no fingerprint. Not committing a map the reader can't check." >&2
  exit 1
fi
if [ "$new" != "$live" ]; then
  echo "regen-if-stale: regenerated fingerprint $new does not match HEAD:$root ($live)." \
       "Uncommitted or untracked files under the root, or the generator and reader disagree." >&2
  exit 1
fi
echo "REGENERATED ${old:-none} -> $new"
