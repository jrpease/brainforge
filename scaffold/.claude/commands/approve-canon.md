---
description: The canon trust gate — promote a verified draft from status:draft to approved.
---

Promote `context/canon/<domain>/<doc>` from `status: draft` to `approved`. **Arguments:**
`$ARGUMENTS` (e.g. `brand/positioning`). Run only after the owner has verified the draft is true.

Steps:
1. Read `context/canon/$ARGUMENTS.md`. **If any `[GAP: …]` markers remain → REFUSE.** List each gap
   and stop. A doc with gaps is not ready to be trusted (authoring rule #4).
2. Confirm the human `owner` with the user (who is accountable for this being correct).
3. Strip the DRAFT banner; set frontmatter `status: approved`, `last-reviewed: <today>`,
   `owner: <name>`.
4. Branch `canon/approve-<domain>-<doc>` + open a PR. This PR is the gate that turns a provisional
   draft into trusted canon — a human merges it.

Never promote a doc with remaining `[GAP]` markers. Never edit the doc's substantive content here —
approval verifies, it does not author (re-run `/draft-canon` if content needs work).
