#!/usr/bin/env bash
# gen-manifest.sh — regenerate .brainforge/brain-manifest.json from the brain's real tree.
#
# Deterministic by contract (golden rule 3): no LLM, no network; git/find/sed/awk/wc only.
# OUTPUT FORMATTING IS A CONTRACT: 2-space indent, one key per line at domain level,
# file entries as single-line objects — dependency-free consumers (the synapse session
# hook, pointer blocks) parse this with grep/sed/awk. Never reformat without a version bump.
#
# Domain = any directory under context/ containing an _index.md.
# Domain files = *.md directly in the domain dir, minus _index.md and README.md,
#                PLUS data files (*.json) the domain emits — those cost real tokens to read.
# tokens = (words * 4 + 2) / 3. Bands: cheap < 3000, normal 3000-10000, expensive > 10000.
#
# SCHEMA 2 (2026-08-12) — token accounting made honest.
#   Schema 1 counted only *.md excluding _index.md, so every domain's `tokens` UNDER-reported
#   its real read cost: _index.md files and emitted data files (e.g. design-system/tokens.json)
#   were invisible. In one real brain that hid ~10,000 tokens across context/ (33,031 reported
#   vs 43,386 actual) — enough for a domain to sit in the "cheap" band while actually being
#   expensive.
#   Now:
#     tokens      = docTokens + indexTokens   <- the honest total, what bands are computed from
#     docTokens   = sum of files[]            <- schema 1's `tokens`, kept for continuity
#     indexTokens = the domain's _index.md
#   files[] now also lists *.json data files. Line format is UNCHANGED (single-line objects,
#   2-space indent) so grep/sed/awk consumers keep working; only the arithmetic changed.
#
# SCHEMA 3 (2026-09-09) — the map can finally say whether it is current, and where it looked.
#   Schema 2 stamped `generatedFrom` = HEAD. You then have to COMMIT the manifest, which creates
#   a new HEAD, so the reader's staleness check could never pass: the commit that lands a fresh
#   map is the commit that invalidates it. No commit sha can fix this — /sync lands the derived
#   change and the regenerated manifest in ONE commit, so the sha carrying the manifest is
#   unknowable while writing the manifest. NOTE: that ruled out a CI job under the SHA scheme,
#   and does NOT under this one — a post-merge job that regenerates and commits touches only
#   .brainforge/, so the context tree is unchanged and the fingerprint still matches. CI
#   regeneration is the clean fix for two branches conflicting on the manifest.
#   Now:
#     contextRoot        = the directory domains were found under (BRAIN_CONTEXT_DIR, default
#                          `context`), so a reader knows where to look without assuming
#     contextFingerprint = the git TREE OBJECT ID of that root's working tree
#   FINGERPRINT CONTRACT: the fingerprint is the git tree oid of contextRoot, nothing else.
#   The reader recomputes it as `git rev-parse HEAD:<contextRoot>` and compares. Identical
#   content gives an identical oid because git trees are content-addressed, so this holds
#   across commits, rebases and squashes, and it is one rev-parse on the read side. Change
#   this definition and you must change synapse/hooks/session-start.sh in the same breath.
#   `generatedFrom` is KEPT, as provenance only — nothing compares against it any more.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

remote=$(git config --get remote.origin.url 2>/dev/null || true)
# Strip any userinfo (https://user:token@host/...). This value is committed and every
# subscriber clones it; nothing reads it but the basename below.
remote=$(printf '%s' "$remote" | sed 's#//[^/@]*@#//#')
brain=$(basename -s .git "${remote:-$PWD}")
sha=$(git rev-parse --verify HEAD 2>/dev/null || echo "unborn")
today=$(date +%F)
# Domains are found under this root. Configurable so a repo whose docs do not live in
# context/ can still emit a valid manifest; the value is recorded in the manifest so a
# reader never has to assume it.
# Precedence: the env var, else the root the existing manifest already records, else the
# default. The manifest is committed; the env var is not, so every documented regenerate path
# (/sync, /upgrade §5a, the README) calls this script bare. Reading the env alone silently
# reverted a non-default-root brain to `context` and emitted a zero-domain map.
root="${BRAIN_CONTEXT_DIR:-}"
if [ -z "$root" ] && [ -f .brainforge/brain-manifest.json ]; then
  root=$(sed -n 's/^  "contextRoot": "\(.*\)",$/\1/p' .brainforge/brain-manifest.json | head -1)
fi
root="${root:-context}"
mkdir -p .brainforge
out=.brainforge/brain-manifest.json

# ctx_tree -> the git tree object id of $root as it exists in the WORKING TREE.
# Computed through a throwaway index (GIT_INDEX_FILE), so the real index is never touched
# and running this never stages anything. Honours .gitignore and includes untracked files,
# which is exactly the set about to be committed. Empty output = not computable; the reader
# treats an empty fingerprint as "cannot check" rather than as "stale".
ctx_tree() {
  local d t
  d=$(mktemp -d 2>/dev/null) || return 0
  GIT_INDEX_FILE="$d/index" git add -A -- "$root" 2>/dev/null || true
  t=$(GIT_INDEX_FILE="$d/index" git write-tree 2>/dev/null || true)
  # --verify -q is load-bearing: plain `rev-parse HEAD:missing` PRINTS its own argument to
  # stdout and signals failure only via exit code, so `|| true` captured the junk string and
  # the documented "empty means not computable" contract could never hold.
  if [ -n "$t" ]; then
    GIT_INDEX_FILE="$d/index" git rev-parse --verify -q "$t:$root" 2>/dev/null || true
  fi
  rm -rf "$d"
}
ctx_fp=$(ctx_tree)

# fm <file> <key> -> a top-level frontmatter value, or empty.
# Reads the --- block rather than a fixed line count: a derived _index.md carries source,
# last-synced, generated-by, title, description..., so `kinds:` below line 20 used to vanish
# and silently reclassify a healthy domain as unclassified.
fm() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1                { next }
    $0 == "---"            { exit }
    index($0, k ":") == 1  { sub("^" k ":[[:space:]]*", ""); print; exit }
  ' "$1"
}

# fm_kinds <file> -> "a, b, c" from any spelling YAML actually allows:
#   kinds: [a, b]  ·  kinds: ["a", "b"]  ·  kinds:\n  - a\n  - b
# Quoted flow lists used to emit ""a"" and produce an INVALID-JSON manifest that every reader
# in this repo hid by stripping quotes; block lists used to yield [] and a false "unclassified".
fm_kinds() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1                { next }
    $0 == "---"            { exit }
    index($0, "kinds:") == 1 {
      v = $0; sub(/^kinds:[[:space:]]*/, "", v)
      sub(/^\[/, "", v); sub(/\]$/, "", v)
      gsub(/[""'"'"']/, "", v)
      if (v != "") { print v; exit }
      block = 1; next
    }
    block {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        gsub(/[""'"'"']/, "", item)
        gsub(/[[:space:]]*$/, "", item)
        if (item != "") out = (out == "" ? item : out ", " item)
        next
      }
      if ($0 ~ /^[^[:space:]]/) { block = 0 }
    }
    END { if (out != "") print out }
  ' "$1"
}

# escape_json <string> -> escape for safe JSON string interpolation (\\ then ")
escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

domain_blocks=""
unclassified=""

# A directory holding content but no _index.md is invisible to the map -- and because the
# fingerprint covers the whole root, the reader is simultaneously told the map is CURRENT.
# That is the third column of the visible-orphan / silent-orphan table: content that is
# neither. Same detection catches a file nested below a domain's top level, since the
# generator only reads a domain at -maxdepth 1.
unindexed=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -f "$d/_index.md" ] && continue
  has=""
  for f in "$d"/*.md "$d"/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in README.md) continue ;; esac
    has=1; break
  done
  [ -n "$has" ] || continue
  unindexed="${unindexed}    \"$(escape_json "$d")\",
"
done <<EOF
$(find "$root" -type d 2>/dev/null | sort)
EOF

while IFS= read -r idx; do
  [ -n "$idx" ] || continue
  dir=$(dirname "$idx")
  title=$(fm "$idx" title); [ -n "$title" ] || title=$(basename "$dir")
  kinds_raw=$(fm_kinds "$idx")
  if [ -n "$kinds_raw" ]; then
    kinds_json=$(printf '%s' "$kinds_raw" | sed 's/[[:space:]]*,[[:space:]]*/", "/g; s/^/"/; s/$/"/')
  else
    kinds_json=""
    unclassified="${unclassified}    \"$(escape_json "$dir")\",
"
  fi

  doc_total=0
  files_json=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      *.json) tok=$(( ( $(wc -c < "$f" | tr -d ' ') + 3 ) / 4 )) ;;
      *)      tok=$(( ( $(wc -w < "$f" | tr -d ' ') * 4 + 2 ) / 3 )) ;;
    esac
    doc_total=$(( doc_total + tok ))
    ftitle=$(sed -n 's/^# //p' "$f" | head -1); [ -n "$ftitle" ] || ftitle=$(basename "$f")
    files_json="${files_json}        { \"path\": \"$(escape_json "$(basename "$f")")\", \"title\": \"$(escape_json "$ftitle")\", \"tokens\": ${tok} },
"
  done <<EOF
$(find "$dir" -maxdepth 1 \( -name '*.md' ! -name '_index.md' ! -name 'README.md' \) -o -maxdepth 1 -name '*.json' | sort)
EOF

  # schema 2: _index.md is a real read cost — count it instead of silently dropping it
  idx_words=$(wc -w < "$idx" | tr -d ' ')
  idx_tok=$(( (idx_words * 4 + 2) / 3 ))
  total=$(( doc_total + idx_tok ))

  if   [ "$total" -lt 3000 ];  then band=cheap
  elif [ "$total" -le 10000 ]; then band=normal
  else                              band=expensive; fi

  files_json=$(printf '%s' "$files_json" | sed '$ s/,$//')
  block="    {
      \"path\": \"$(escape_json "$dir")\",
      \"title\": \"$(escape_json "$title")\",
      \"kinds\": [${kinds_json}],
      \"tokens\": ${total},
      \"docTokens\": ${doc_total},
      \"indexTokens\": ${idx_tok},
      \"band\": \"${band}\",
      \"files\": [
${files_json}
      ]
    },
"
  domain_blocks="${domain_blocks}${block}"
done <<EOF
$(find "$root" -name _index.md -type f 2>/dev/null | sort)
EOF

domain_blocks=$(printf '%s' "$domain_blocks" | sed '$ s/,$//')
unclassified=$(printf '%s' "$unclassified" | sed '$ s/,$//')
unindexed=$(printf '%s' "$unindexed" | sed '$ s/,$//')

{
  printf '{\n'
  printf '  "schema": 3,\n'
  printf '  "brain": "%s",\n' "$brain"
  printf '  "remote": "%s",\n' "$remote"
  printf '  "contextRoot": "%s",\n' "$(escape_json "$root")"
  printf '  "contextFingerprint": "%s",\n' "$ctx_fp"
  printf '  "generatedFrom": "%s",\n' "$sha"
  printf '  "generatedAt": "%s",\n' "$today"
  printf '  "domains": [\n'
  printf '%s\n' "$domain_blocks"
  printf '  ],\n'
  printf '  "unclassified": [\n'
  [ -n "$unclassified" ] && printf '%s\n' "$unclassified"
  printf '  ],\n'
  printf '  "unindexed": [\n'
  [ -n "$unindexed" ] && printf '%s\n' "$unindexed"
  printf '  ]\n'
  printf '}\n'
} > "$out"

echo "manifest: $(printf '%s' "$domain_blocks" | grep -c "\"path\": \"$root/" || true) domains ($root) -> $out"

# The fingerprint deliberately measures what is ABOUT TO BE COMMITTED, so untracked files
# count. A stray notes-wip.md or a mergetool .orig therefore makes every reader's map read
# permanently stale from a state only this laptop can see. Name them at the one moment they
# can be fixed.
untracked=$(git ls-files --others --exclude-standard -- "$root" 2>/dev/null || true)
if [ -n "$untracked" ]; then
  echo "  ⚠ $(printf '%s\n' "$untracked" | grep -c .) untracked file(s) under $root/ are in this fingerprint"
  echo "    and will NOT be in your commit, so readers will see the map as stale. Commit or remove:"
  printf '%s\n' "$untracked" | sed 's/^/      /'
fi
[ -n "$unindexed" ] && echo "  ⚠ unindexed (content the map cannot see): $(printf '%s\n' "$unindexed" | grep -c .) dir(s)"
exit 0
