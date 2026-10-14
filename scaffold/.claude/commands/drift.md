---
description: Reconcile authored canon against derived reality — flag contradictions and draft canon fixes for the stale ones.
---

Run the drift loop in `pipeline/drift-report.md`. This is the manager-layer flagship: **a detected
drift becomes a draft canon fix you approve** — the same ingest → draft → approve → PR loop, initiated
by the tool instead of remembered by you.

**Arguments:** `$ARGUMENTS` — empty (delta-scope: only domains changed since the last review) or a
domain name (`brand` | `product` | `design` | `eng` | `analytics` | `company`) to force a full re-check of one.

Do this:

1. **Delta-scope (golden rule #1).** Read `.brainforge/last-drift-review` (the last-reviewed commit
   SHA). Scope the analysis to domains whose `context/canon/<domain>/` or `context/derived/…` changed
   since that SHA (`git diff --name-only <sha> HEAD -- context/canon context/derived`). No watermark,
   or a domain arg → check that scope in full. With a domain arg and a watermark, still run that diff
   and keep its path list: step 5 needs it to decide whether to stamp. Say what you scoped and why.

2. **Compare canon vs derived** for each in-scope domain — the `canon claim` vs `derived fact` pattern
   in `pipeline/drift-report.md`. Analysis is **read-only**; write any long working notes to `scratch/`.

3. **Classify each contradiction:**
   - **Canon-stale** — derived is a *hard factual reality* (a framework/version, a count, a token
     value, a shipped name/route) and canon factually contradicts it. → **Offer to draft the fix.**
   - **Implementation-drift or ambiguous** — someone shipped something that violates canon, OR it is
     genuinely unclear which side is wrong (subjective / principle-level). → **Flag only:** report it,
     recommend the upstream fix, open no draft. **When in doubt, flag — never auto-draft.** Hold this
     line hardest for `brand` (subjective, low source material).

4. **For each canon-stale drift the user accepts,** draft the fix by running the `/draft-canon` loop
   (`authoring/README.md`) on `<domain>/<doc>`, with **the drift evidence as the ingested material**
   (canon claim + the derived fact + where each lives) and the existing approved doc as the section
   skeleton (the existing doc satisfies `/draft-canon`'s skeleton step — do not look for a `templates/`
   file). The draft:
   - asserts **only what the derived fact shows**, citing it as `> _source: <derived file>_`
     (**ingest, don't invent**);
   - marks any change needing human judgment (was this an intentional decision or a mistake? does new
     copy imply a real tone shift?) as `[GAP: needs human input]` — never a guessed sentence;
   - lands `status: draft` + the loud DRAFT banner via the `/draft-canon` PR. `/approve-canon` remains
     the only path to `approved` and **refuses on any `[GAP]`** — do not bypass it.

5. **Stamp the watermark — drift found or not, but only if this run covered everything it vouches for.**
   The watermark records "everything up to this commit has been reviewed", so stamp it only when that is
   true: a run with no domain argument, or a domain-scoped run that covered every path step 1's diff
   names (each is under `context/canon/<domain>/` or a derived folder this run compared). Then write the current `git rev-parse HEAD` into
   `.brainforge/last-drift-review` and commit that one file to the current branch, so the session-start
   nudge clears until the next canon edit or sync. (This cursor is manager state, not canon/derived, so
   it commits directly; drafts still go through their PR.)

   **A domain-scoped run that leaves other changed scopes unreviewed does not stamp**, and neither does
   a domain-scoped run with no watermark yet. Stamping there would clear the nudge for scopes nobody
   looked at. Say so in the output instead, naming them: "Reviewed `design` only; watermark not
   stamped. Still unreviewed since `<sha>`: `canon/brand`, `derived/notion`." The nudge stays lit until
   a full run.

Read-only analysis except for: `scratch/` notes, the draft PR(s), and the watermark stamp. Never
auto-resolve a drift and never mark anything `approved` — the owner decides, and `/approve-canon` gates.
