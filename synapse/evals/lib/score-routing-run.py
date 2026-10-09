#!/usr/bin/env python3
"""Score one `claude -p --output-format stream-json` run against a case.yaml's graders.

Used by synapse/evals/routing-smoke.sh. Stdlib only.

GRADER SEMANTICS — every field here is load-bearing. An earlier version of this
file ignored three of them and produced confidently wrong results in both
directions, so they are spelled out:

  input_match   A REGEX, not a substring. build-prototype uses
                "canon/design|design-system" — an alternation. Substring
                matching silently fails it.
  match         "not_contains" INVERTS the result. Two cases assert an absence
                (no hex colour when ungrounded; no exclamation marks in brand
                copy). Ignoring this reports a correct run as failed.
  min / max     On tool_used. `min: 0, max: 0` means "this tool must NOT be
                called on this input" — an absence assertion. Checking only
                `len(hits) >= min` makes it `>= 0`, which is always true, so the
                grader passes even when the thing it forbids happened.
  arm           Which ablation arm scores this grader. There is only one arm
                here (no --plugin/--no-plugin delta), so it is recorded and
                ignored rather than silently dropped.

  llm           NOT SCORED — needs a judge model, which the real harness owns.
                Reported as SKIP so a case leaning on one is never called green.

Any grader field this file does not understand is reported, not ignored.

Usage: score-routing-run.py <case.json> <run.jsonl>
"""
import json
import re
import sys

KNOWN = {
    "regex": {"type", "name", "target", "pattern", "flags", "match", "arm", "weight"},
    "tool_used": {"type", "name", "tool", "input_match", "min", "max", "arm", "weight"},
    "tool_order": {"type", "name", "before", "after", "arm", "weight"},
}


def load_run(path):
    """-> (final_text, [(tool_name, joined_input_values)], cost, turns, error)"""
    final, tools, cost, turns, err = "", [], 0.0, 0, None
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("type") == "assistant":
                for b in d.get("message", {}).get("content", []):
                    if b.get("type") == "tool_use":
                        vals = " ".join(
                            str(v) for v in b.get("input", {}).values()
                            if isinstance(v, (str, int, float))
                        )
                        tools.append((b.get("name", ""), vals))
            elif d.get("type") == "result":
                final = str(d.get("result") or "")
                cost = d.get("total_cost_usd") or 0.0
                turns = d.get("num_turns") or 0
                if d.get("is_error"):
                    err = d.get("subtype") or "error"
    return final, tools, cost, turns, err


def compile_flags(spec):
    f = 0
    spec = spec or ""
    if "s" in spec:
        f |= re.S
    if "i" in spec:
        f |= re.I
    if "m" in spec:
        f |= re.M
    return f


def find(tools, tool_name, needle):
    """Indices of tool calls matching name and input REGEX. Empty needle = any."""
    rx = re.compile(needle) if needle else None
    hits = []
    for i, (name, vals) in enumerate(tools):
        if tool_name and name != tool_name:
            continue
        if rx and not rx.search(vals):
            continue
        hits.append(i)
    return hits


def score(g, final, tools, trace):
    """-> (ok, note) ; ok is None for 'not scorable here'."""
    gtype = g.get("type")

    if gtype == "regex":
        hay = trace if g.get("target") == "trace" else final
        present = re.search(g.get("pattern", ""), hay, compile_flags(g.get("flags"))) is not None
        if g.get("match") == "not_contains":
            return (not present), "absence"
        return present, ""

    if gtype == "tool_used":
        hits = len(find(tools, g.get("tool"), g.get("input_match", "")))
        lo = g.get("min")
        hi = g.get("max")
        ok = True
        if lo is not None and hits < int(lo):
            ok = False
        if hi is not None and hits > int(hi):
            ok = False
        if lo is None and hi is None and hits < 1:
            ok = False
        note = "absence" if (hi is not None and int(hi) == 0) else ""
        return ok, note

    if gtype == "tool_order":
        b, a = g.get("before", {}), g.get("after", {})
        bh = find(tools, b.get("tool"), b.get("input_match", ""))
        ah = find(tools, a.get("tool"), a.get("input_match", ""))
        return (bool(bh) and bool(ah) and min(bh) < max(ah)), ""

    return None, f"{gtype} — needs the real harness"


def main():
    case = json.load(open(sys.argv[1]))
    final, tools, cost, turns, err = load_run(sys.argv[2])
    trace = final + "\n" + "\n".join(f"{n} {v}" for n, v in tools)

    lines, failed, skipped = [], 0, 0
    if err:
        lines.append(f"   run errored: {err}")
        failed += 1

    for g in case.get("graders", []):
        gname = g.get("name", g.get("type"))
        unknown = set(g) - KNOWN.get(g.get("type"), set(g))
        ok, note = score(g, final, tools, trace)

        if ok is None:
            lines.append(f"   SKIP {gname} ({note})")
            skipped += 1
            continue

        tag = "ok  " if ok else "FAIL"
        suffix = f"  [{note}]" if note else ""
        if unknown:
            suffix += f"  [unhandled: {','.join(sorted(unknown))}]"
        lines.append(f"   {tag} {gname}{suffix}")
        if not ok:
            failed += 1

    print("\n".join(lines))
    print(f"   VERDICT: {'PASS' if failed == 0 else 'FAIL'}  (${cost:.4f}, {turns} turns"
          + (f", {skipped} skipped)" if skipped else ")"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
