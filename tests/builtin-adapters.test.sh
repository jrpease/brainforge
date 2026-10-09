#!/usr/bin/env bash
# The sync docs name the built-in adapter types, so a model can tell "built-in whose gate script
# is missing" (not-checked) from "custom adapter with no gate script" (runs its own §1). That list
# must match the gate scripts that actually ship, in every doc that routes on it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
shipped=$(cd "$ROOT/scaffold/.brainforge" && ls gate-*.sh | sed 's/^gate-//; s/\.sh$//' | sort | tr '\n' ' ')
[ -n "$shipped" ] || fail "no gate scripts found"
for doc in scaffold/.claude/commands/sync.md scaffold/pipeline/sync-all.md scaffold/pipeline/sync-health.md; do
  line=$(grep -m1 'Built-in types:' "$ROOT/$doc") || fail "$doc does not name the built-in types"
  named=$(echo "$line" | sed 's/.*Built-in types://' | grep -oE '`[a-z]+`' | tr -d '`' | sort | tr '\n' ' ')
  [ "$named" = "$shipped" ] || fail "$doc names [$named] but gate scripts ship for [$shipped]"
done
echo "PASS builtin-adapters"
