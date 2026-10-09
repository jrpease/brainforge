#!/usr/bin/env bash
# Each command file whose python is extracted with awk '/^```python$/,/^```$/' must hold exactly
# ONE ```python fence: that awk range joins every python fence in the file into one script, so a
# second fence silently breaks the extraction (commands/forge.md §3 bootstraps fresh installs
# from upgrade.md this way).
# Usage: fence-contract.test.sh [file ...]   (default: the two files that carry the contract)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -eq 0 ]; then
  set -- "$ROOT/commands/upgrade.md" "$ROOT/synapse/commands/subscribe.md"
fi

bad=0
for f in "$@"; do
  [ -r "$f" ] || { echo "FAIL: $f: not readable"; bad=1; continue; }
  n=$(grep -c '^```python$' "$f" || true)
  if [ "$n" -ne 1 ]; then
    echo "FAIL: $f: expected exactly one \`\`\`python fence, found $n"
    bad=1
  fi
done

[ "$bad" -eq 0 ] || exit 1
echo "PASS fence-contract"
