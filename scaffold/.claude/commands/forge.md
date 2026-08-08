---
description: Guided depth-first setup — fill one domain end-to-end (lead with a derivable win), then offer the next. Resumable.
---

Walk the user through setting up this brain, **one domain at a time**, following the method in
[`setup/README.md`](../../setup/README.md). Wrap the existing commands inline — the user should
not have to type each one.

**Arguments:** `$ARGUMENTS` — optional. A domain name (`eng` | `design` | `product` |
`analytics` | `brand`) jumps straight to that domain's loop. Empty = compute the ladder and route.

Always:
1. **Guard** — confirm a `sources.json` exists at the repo root. If not, stop and tell the user to
   run `/forge` from inside a scaffolded brain.
2. **Compute the status ladder by inspecting the brain** (canon frontmatter, `sources.json`,
   `.sync-state.json`) — there is **no walk-state file**. Report each domain as `not-started`,
   `in-progress @ <rung>`, or `complete`.
3. **Route:** resume any `in-progress` domain at its next rung; otherwise offer the `not-started`
   menu and **recommend the most derivable fast-win (eng/design); defer brand**.
4. **Drive the loop inline** (`setup/README.md` §3): scaffold → ingest → interview → `/draft-canon`
   → `/approve-canon` → wire adapter (`/add-source` or `/add-adapter`) → `/sync` → **read it back**.
5. **Honor the two trust gates** — `/approve-canon` refuses on any `[GAP]`; every sync lands via a
   PR, never a direct write. Never relax the canon guardrail or the six golden rules.
6. After the read-back payoff, offer the next domain or stop (resumable later).

Skip the adapter/sync rungs for authored-only domains (brand) — the loop ends at approved canon.
