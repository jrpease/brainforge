#!/usr/bin/env bash
# The session-start sync-health tripwire: runs the ACTUAL session-start.sh the scaffold ships
# against constructed brains (pub #26: one source that never synced, in a brain that has).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SS="$ROOT/scaffold/.brainforge/session-start.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
[ -f "$SS" ] || fail "scaffold has no .brainforge/session-start.sh"
grep -q 'sync-state.json' "$SS" || fail "session-start.sh has no sync-health tripwire"

# brain <name> <.sync-state.json body> — a brain dir holding only that state file
brain() { mkdir -p "$TMP/$1"; printf '%s\n' "$2" > "$TMP/$1/.sync-state.json"; }
# The script also prints the pull line (and the drift nudge where derived docs exist), so
# "silent" means no sync-health line, not empty output.
run() { CLAUDE_PROJECT_DIR="$TMP/$1" bash "$SS"; }
fires()  { out=$(run "$1") || fail "hook errored on $1"; echo "$out" | grep -q 'Context:' || fail "script did not run for $1 (got: $out)"; echo "$out" | grep -q 'Sync health' || fail "tripwire must fire for $1 (got: $out)"; }
silent() { out=$(run "$1") || fail "hook errored on $1"; echo "$out" | grep -q 'Context:' || fail "script did not run for $1 (got: $out)"; echo "$out" | grep -q 'Sync health' && fail "tripwire must be silent for $1 (got: $out)"; return 0; }

# (a) a brain that has never synced: /add-source wrote the slot, nothing flipped it
brain never '{
  "version": 1,
  "repos": {
    "web": {
      "synced": false
    }
  },
  "lastFullSync": null
}'
fires never

# (b) one source never synced, in a brain where another source has (lastFullSync is set)
brain one-unsynced '{
  "version": 1,
  "repos": {
    "web": {
      "lastSha": "abc123",
      "synced": true
    },
    "api": {
      "synced": false
    }
  },
  "lastFullSync": "2026-09-01"
}'
fires one-unsynced

# (c) an old-format brain: no flag anywhere, a wired slot and lastFullSync null (as before)
brain old-format '{
  "version": 1,
  "repos": {
    "web": {}
  },
  "lastFullSync": null
}'
fires old-format

# the existing source: TODO rule still fires on its own
brain todo '{
  "version": 1,
  "lastFullSync": "2026-09-01"
}'
mkdir -p "$TMP/todo/context/derived/web"
printf -- '---\nsource: TODO\n---\n' > "$TMP/todo/context/derived/web/site-map.md"
fires todo

# silent: a fully synced brain
brain synced '{
  "version": 1,
  "repos": {
    "web": {
      "lastSha": "abc123",
      "synced": true
    }
  },
  "lastFullSync": "2026-09-01"
}'
silent synced

# silent: the fresh scaffold state (nothing wired; its $comment must not trip the grep)
mkdir -p "$TMP/fresh"; cp "$ROOT/scaffold/.sync-state.json" "$TMP/fresh/.sync-state.json"
silent fresh

# silent: a "synced" key nested inside a fingerprint is not the slot's flag (pub #36)
brain nested '{
  "version": 1,
  "repos": {
    "web": {
      "fingerprint": {
        "synced": false
      },
      "synced": true
    }
  },
  "lastFullSync": "2026-09-01"
}'
silent nested

echo "PASS sync-tripwire"
