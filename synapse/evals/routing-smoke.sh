#!/usr/bin/env bash
# routing-smoke.sh — run the routing eval cases WITHOUT `claude plugin eval`.
#
# WHY THIS EXISTS
#   synapse/routing/README.md requires a passing eval run for every intents.json
#   change. `claude plugin eval` is gated behind org-level early access, so for
#   anyone without that entitlement the rule is unenforceable and the cases in
#   synapse/evals/routing/ are unrun documentation. This executes them with
#   `claude -p` instead.
#
# WHAT IT IS NOT
#   Not a replacement for the harness. No ablation arm (no with/without-plugin
#   delta), no LLM-judge graders, one run per case rather than several. A pass
#   here means "the behaviour happened once"; the harness means "it holds up".
#   Prefer the harness whenever it is available to you.
#
# ISOLATION MATTERS — READ BEFORE CHANGING THE FLAGS
#   Without --restricted and --strict-mcp-config this inherits the operator's
#   whole environment. Measured on the first attempt: the run ignored the brain
#   entirely, spent 20 turns searching the operator's real Gmail, Slack, Notion
#   and Google Drive through their personal MCP servers, cost $1.08, and
#   answered "not found". With isolation: 11 turns, $0.22, correct.
#     --restricted          ignore user/project/local settings, drop Bash and
#                           the other code-running tools, confine file tools to
#                           the working directory
#     --strict-mcp-config   use only MCP servers from --mcp-config (none here),
#                           so no personal MCP servers load
#     --plugin-dir          load THIS CHECKOUT's synapse, not the installed one
#   Note --allowedTools grants permission; it does not shrink the tool set. The
#   two isolation flags are what actually contain the run.
#
# USAGE
#   bash synapse/evals/routing-smoke.sh           # every case
#   bash synapse/evals/routing-smoke.sh stranded  # cases whose name contains "stranded"
#
# COST
#   Real tokens, roughly $0.20-0.30 per case. Printed per case and as a total.
#
# Lives under synapse/evals/ so it SHIPS with the plugin: public users hit the
# same early-access gate and need this just as much. Deliberately not in tests/,
# which is unpublished and whose *.test.sh suite must stay offline and free.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN="$ROOT/synapse"
CASEDIR="$PLUGIN/evals/routing"
FILTER="${1:-}"

command -v claude >/dev/null || { echo "FAIL: claude CLI not on PATH"; exit 1; }
command -v ruby   >/dev/null || { echo "FAIL: ruby needed to read case.yaml"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass_n=0; fail_n=0; skip_n=0; failed_cases=""

for case_yaml in "$CASEDIR"/*/case.yaml; do
  name=$(basename "$(dirname "$case_yaml")")
  [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue ;; esac

  # case.yaml -> json (stdlib ruby; pyyaml is not installed and we do not add deps)
  cj="$TMP/$name.json"
  ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$case_yaml" > "$cj" 2>/dev/null \
    || { echo "FAIL $name — could not parse case.yaml"; fail_n=$((fail_n+1)); continue; }

  prompt=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["execution"]["prompt"])' "$cj")
  maxturns=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["execution"].get("max_turns",12))' "$cj")
  tools=$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["execution"].get("allowed_tools",["Read","Glob","Grep","Skill"])))' "$cj")

  # scaffold the sandbox exactly as the harness would
  work="$TMP/work-$name"; mkdir -p "$work"
  scaffold="$(dirname "$case_yaml")/scaffold.sh"
  if [ -f "$scaffold" ]; then
    ( cd "$work" && bash "$scaffold" ) >/dev/null 2>&1 \
      || { echo "FAIL $name — scaffold_script failed"; fail_n=$((fail_n+1)); continue; }
  fi

  echo "── $name"
  jsonl="$TMP/$name.jsonl"
  # shellcheck disable=SC2086
  ( cd "$work" && claude -p "$prompt" \
      --output-format stream-json --verbose \
      --restricted --strict-mcp-config \
      --allowedTools $tools \
      --plugin-dir "$PLUGIN" \
      --max-turns "$maxturns" ) > "$jsonl" 2>"$TMP/$name.err"

  if [ ! -s "$jsonl" ]; then
    echo "   FAIL — no output from claude (see $TMP/$name.err)"
    fail_n=$((fail_n+1)); failed_cases="$failed_cases $name"; continue
  fi

  # score
  out=$(python3 "$PLUGIN/evals/lib/score-routing-run.py" "$cj" "$jsonl")
  echo "$out"
  verdict=$(printf '%s' "$out" | sed -n 's/^ *VERDICT: \([A-Z]*\).*/\1/p' | head -1)
  case "$verdict" in
    PASS) pass_n=$((pass_n+1)) ;;
    *)    fail_n=$((fail_n+1)); failed_cases="$failed_cases $name" ;;
  esac
  skipped=$(printf '%s' "$out" | grep -c 'SKIP ' || true)
  skip_n=$((skip_n + skipped))
done

echo
echo "════ routing smoke: $pass_n passed, $fail_n failed, $skip_n graders skipped"
[ -n "$failed_cases" ] && echo "     failed:$failed_cases"
[ "$fail_n" -eq 0 ] || exit 1
echo "     NOTE: not a substitute for \`claude plugin eval\` — single run, no ablation arm,"
echo "           LLM-judge graders unscored. See the header of this file."
exit 0
