#!/usr/bin/env bash
# Every emitted session hook must stay valid shell for ANY org name (F1): the one thin
# settings.json command and the session-start.sh script it runs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/scaffold/.claude/settings.json"
SS="$ROOT/scaffold/.brainforge/session-start.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Hostile but entirely ordinary org names.
ORGS=("Levi's" 'He said "hi"' 'A&B $HOME `x`' 'Ben & Jerry’s')

for ORG in "${ORGS[@]}"; do
  python3 - "$SETTINGS" "$ORG" "$TMP" <<'PY'
import json, pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
org, tmp = sys.argv[2], pathlib.Path(sys.argv[3])
emitted = raw.replace(b"{{ORG}}", org.encode())          # emit = raw byte replace, no escaping
(tmp / "settings.json").write_bytes(emitted)
cfg = json.loads(emitted)                                 # must still be valid JSON
cmds = [h["command"] for m in cfg["hooks"]["SessionStart"] for h in m["hooks"]]
for i, c in enumerate(cmds):
    (tmp / f"hook{i}.sh").write_text(c + "\n")
print(len(cmds))
PY
  n=$(ls "$TMP"/hook*.sh 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || fail "expected 1 hook command, extracted $n for org [$ORG]"
  for h in "$TMP"/hook*.sh; do
    bash -n "$h" || fail "hook $(basename "$h") is not valid shell for org [$ORG]"
  done
  python3 - "$SS" "$ORG" "$TMP/session-start.sh" <<'PY'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
pathlib.Path(sys.argv[3]).write_bytes(raw.replace(b"{{ORG}}", sys.argv[2].encode()))
PY
  bash -n "$TMP/session-start.sh" || fail "session-start.sh is not valid shell for org [$ORG]"
  rm -f "$TMP"/hook*.sh "$TMP/session-start.sh"
done
echo "PASS org-name-safety"
