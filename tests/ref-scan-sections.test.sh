#!/usr/bin/env bash
# /upgrade §5's section-reference scan: a `<path> § <section>` reference whose heading is gone must
# be named, and a good one must not (pub #30). Runs the bash block exactly as upgrade.md ships it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# the bash fence in §5 that checks § references
awk '/^## 5\. /{s=1} /^## 5a\. /{s=0}
     s && /^```bash$/ {b=1; buf=""; next}
     s && b && /^```$/ {b=0; if (buf ~ /§/) {printf "%s", buf; exit}; next}
     s && b {buf = buf $0 "\n"}' "$ROOT/commands/upgrade.md" \
  | sed 's|"<brain>"|"$1"|; s|"<classifier-output>"|"$2"|' > "$TMP/scan.sh"
grep -q '§' "$TMP/scan.sh" || fail "could not extract the section-reference block from upgrade.md §5"

B="$TMP/brain"
mkdir -p "$B/pipeline/adapters" "$B/.claude/commands" "$B/context/derived/x"
cat > "$B/pipeline/README.md" <<'EOF'
# Pipeline
## Defaults — so a rule always has something to compare against
EOF
cat > "$B/pipeline/adapters/github.md" <<'EOF'
# GitHub
## 0a-bis. Read the FETCHED REF
EOF
cat > "$B/.claude/commands/sync.md" <<'EOF'
Good named: the weekly default (`pipeline/README.md` § Defaults).
Good numbered: see `pipeline/adapters/github.md` §0a-bis for the fetched ref.
Broken: see `pipeline/adapters/github.md` §7 for nothing.
EOF
# derived docs are regenerated, never scanned
printf 'see `pipeline/README.md` § Nowhere\n' > "$B/context/derived/x/doc.md"

# --- case A: only the broken reference is named ---
bash "$TMP/scan.sh" "$B" "$TMP/no-actions.txt" > "$TMP/a.txt"
echo "--- case A (fixture) ---"; cat "$TMP/a.txt"
[ "$(wc -l < "$TMP/a.txt" | tr -d ' ')" = 1 ] || fail "expected exactly one miss"
grep -qF '.claude/commands/sync.md:3 → `pipeline/adapters/github.md` §7: no such section' "$TMP/a.txt" \
  || fail "the broken §7 reference was not named"

# --- case B: a miss whose target this run flagged is marked Flagged ---
printf 'FLAG-MODIFIED\tpipeline/adapters/github.md\n' > "$TMP/actions.txt"
bash "$TMP/scan.sh" "$B" "$TMP/actions.txt" > "$TMP/b.txt"
echo "--- case B (flagged target) ---"; cat "$TMP/b.txt"
[ "$(wc -l < "$TMP/b.txt" | tr -d ' ')" = 1 ] || fail "flagged: expected exactly one miss"
grep -qF -- '- [ ] **Flagged** .claude/commands/sync.md:3 → `pipeline/adapters/github.md` §7' "$TMP/b.txt" \
  || fail "flagged: the miss was not marked Flagged"

# --- case C: the shipped scaffold, as a brain root, has no misses ---
bash "$TMP/scan.sh" "$ROOT/scaffold" "$TMP/no-actions.txt" > "$TMP/c.txt"
echo "--- case C (scaffold/) ---"; cat "$TMP/c.txt"
[ ! -s "$TMP/c.txt" ] || fail "scaffold/: section references with no matching heading"

echo "PASS ref-scan-sections"
