#!/usr/bin/env bash
# gen-manifest.sh — regenerate .brainforge/brain-manifest.json from the brain's real tree.
#
# Deterministic by contract (golden rule 3): no LLM, no network; git/find/sed/awk/wc only.
# OUTPUT FORMATTING IS A CONTRACT: 2-space indent, one key per line at domain level,
# file entries as single-line objects — dependency-free consumers (the synapse session
# hook, pointer blocks) parse this with grep/sed/awk. Never reformat without a version bump.
#
# Domain = any directory under context/ containing an _index.md.
# Domain files = *.md directly in the domain dir, minus _index.md and README.md.
# tokens = (words * 4 + 2) / 3. Bands: cheap < 3000, normal 3000-10000, expensive > 10000.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

remote=$(git config --get remote.origin.url 2>/dev/null || true)
brain=$(basename -s .git "${remote:-$PWD}")
sha=$(git rev-parse --verify HEAD 2>/dev/null || echo "unborn")
today=$(date +%F)
mkdir -p .brainforge
out=.brainforge/brain-manifest.json

# fm <file> <key> -> first frontmatter value in the first 20 lines, or empty
fm() { sed -n "1,20s/^$2:[[:space:]]*//p" "$1" | head -1; }

# escape_json <string> -> escape for safe JSON string interpolation (\\ then ")
escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

domain_blocks=""
unclassified=""

while IFS= read -r idx; do
  [ -n "$idx" ] || continue
  dir=$(dirname "$idx")
  title=$(fm "$idx" title); [ -n "$title" ] || title=$(basename "$dir")
  kinds_raw=$(fm "$idx" kinds | sed 's/^\[//; s/\]$//')
  if [ -n "$kinds_raw" ]; then
    kinds_json=$(printf '%s' "$kinds_raw" | sed 's/[[:space:]]*,[[:space:]]*/", "/g; s/^/"/; s/$/"/')
  else
    kinds_json=""
    unclassified="${unclassified}    \"$(escape_json "$dir")\",\n"
  fi

  total=0
  files_json=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    words=$(wc -w < "$f" | tr -d ' ')
    tok=$(( (words * 4 + 2) / 3 ))
    total=$(( total + tok ))
    ftitle=$(sed -n 's/^# //p' "$f" | head -1); [ -n "$ftitle" ] || ftitle=$(basename "$f")
    files_json="${files_json}        { \"path\": \"$(escape_json "$(basename "$f")")\", \"title\": \"$(escape_json "$ftitle")\", \"tokens\": ${tok} },\n"
  done <<EOF
$(find "$dir" -maxdepth 1 -name '*.md' ! -name '_index.md' ! -name 'README.md' | sort)
EOF

  if   [ "$total" -lt 3000 ];  then band=cheap
  elif [ "$total" -le 10000 ]; then band=normal
  else                              band=expensive; fi

  files_json=$(printf '%b' "$files_json" | sed '$ s/,$//')
  block="    {\n"
  block="${block}      \"path\": \"$(escape_json "$dir")\",\n"
  block="${block}      \"title\": \"$(escape_json "$title")\",\n"
  block="${block}      \"kinds\": [${kinds_json}],\n"
  block="${block}      \"tokens\": ${total},\n"
  block="${block}      \"band\": \"${band}\",\n"
  block="${block}      \"files\": [\n${files_json}\n      ]\n"
  block="${block}    },\n"
  domain_blocks="${domain_blocks}${block}"
done <<EOF
$(find context -name _index.md -type f 2>/dev/null | sort)
EOF

domain_blocks=$(printf '%b' "$domain_blocks" | sed '$ s/,$//')
unclassified=$(printf '%b' "$unclassified" | sed '$ s/,$//')

{
  printf '{\n'
  printf '  "brain": "%s",\n' "$brain"
  printf '  "remote": "%s",\n' "$remote"
  printf '  "generatedFrom": "%s",\n' "$sha"
  printf '  "generatedAt": "%s",\n' "$today"
  printf '  "domains": [\n'
  printf '%s\n' "$domain_blocks"
  printf '  ],\n'
  printf '  "unclassified": [\n'
  [ -n "$unclassified" ] && printf '%s\n' "$unclassified"
  printf '  ]\n'
  printf '}\n'
} > "$out"

echo "manifest: $(printf '%s' "$domain_blocks" | grep -c '"path": "context/' || true) domains -> $out"
