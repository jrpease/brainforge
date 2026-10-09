#!/usr/bin/env bash
# Index size limits (backlog spec D6/D16): /sync checks _index.md rows from the manifest's indexTokens, so the three old
# "no token count for _index.md" caveats must be gone. A shallow text test: there is no harness
# that runs command prose, so this proves only that the caveat sentences were removed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bad=0
check() { # <file> <literal sentence that must not remain>
  if grep -qF -- "$2" "$ROOT/$1"; then echo "FAIL: $1 still says: $2"; bad=1; fi
}
check scaffold/.claude/commands/sync.md 'Rule 6 cannot be applied to one'
check scaffold/pipeline/README.md 'a per-`_index.md` envelope does not fire yet'
check scaffold/pipeline/ADAPTER-TEMPLATE.md 'row is a **manual** check for now'
[ "$bad" -eq 0 ] || exit 1
echo "PASS sync-rules"
