#!/usr/bin/env bash
# Test-only gh stand-in. Link it into place as $TMP/bin/gh and put $TMP/bin first on PATH.
# Needs GH_STUB_DIR. Every call's arguments are appended to $GH_STUB_DIR/calls.log, one line,
# space-separated; a body passed as `--body-file -` is read from stdin into $GH_STUB_DIR/body.last.
#   api …/issues… prints $GH_STUB_DIR/issues.json (default [])
#   issue create  prints https://github.com/o/b/issues/7
#   anything else prints nothing
# If $GH_STUB_DIR/fail exists, every call exits 1 after logging, so a test can stand in for an
# expired or under-scoped token.
: "${GH_STUB_DIR:?GH_STUB_DIR must point at a directory}"
printf '%s\n' "$*" >> "$GH_STUB_DIR/calls.log"
prev=""
for a in "$@"; do
  if [ "$prev" = "--body-file" ] && [ "$a" = "-" ]; then cat > "$GH_STUB_DIR/body.last"; fi
  prev=$a
done
[ -e "$GH_STUB_DIR/fail" ] && { echo "gh: HTTP 403: Resource not accessible by personal access token" >&2; exit 1; }
case "$1 ${2:-}" in
  "api repos/{owner}/{repo}/issues"*) if [ -f "$GH_STUB_DIR/issues.json" ]; then cat "$GH_STUB_DIR/issues.json"; else echo "[]"; fi ;;
  "issue create") echo "https://github.com/o/b/issues/7" ;;
esac
exit 0
