---
description: Draft a canon doc from real material (ingest → interview → draft). Loudly provisional.
---

Author a `context/canon/<domain>/<doc>` document by running the ingest → interview → draft loop in
`authoring/README.md`. **Arguments:** `$ARGUMENTS` (e.g. `brand/positioning`).

Steps:
1. Resolve the section skeleton `authoring/templates/$ARGUMENTS.md`. If none exists, say so and
   offer to create a terse skeleton first — **do not invent a doc with no structure.**
2. Ask the user what material to ingest (file paths / URLs). Read it, plus any relevant
   `context/derived/`. **Ingest, don't invent** (authoring rule #1).
3. Interview: for each skeleton section the material did NOT cover, ask the user one question at a
   time. Never re-ask what the material answered. Prefer a `[GAP]` over interrogating (rule #2).
4. Write `context/canon/$ARGUMENTS.md` per the guardrail (rule #3): `status: draft`, the loud DRAFT
   banner, per-section `> _source: …_` provenance or `[GAP: …]` where unfilled.
5. Branch `canon/draft-<domain>-<doc>` + open a PR. Summarize which sections are filled vs `[GAP]`.

Never write a canon doc directly to main, and never mark anything `status: approved` here — that is
`/approve-canon`'s gate alone.
