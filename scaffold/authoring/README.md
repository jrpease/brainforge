# Authoring — how raw material becomes `canon/` truth

These are instructions the maintainer's LLM follows to **author canon**. Canon is human-authored
truth; this method turns blank-page paralysis into *editing* by bootstrapping a draft from real
material — but it **never lets an unverified draft masquerade as truth.** The canon-side rules,
applied by every authoring command:

## The loop
ingest → interview → draft → approve. `/draft-canon` runs ingest→interview→draft; `/approve-canon`
is the gate. (This is the canon counterpart to the sync runtime in `pipeline/`.)

## 1. Ingest, don't invent
Gather only real material the user points at (decks, site copy, PRDs, READMEs, R&D docs) plus
existing `context/derived/` facts. Every claim in a draft traces to ingested material or a user
answer. Nothing is invented to fill space.

## 2. Interview gaps only, one at a time
Diff the material against the doc's section skeleton (`templates/<domain>/<doc>.md`). Ask the user
**only** about sections the material didn't cover — never re-ask what the material answered. One
question per turn. Prefer leaving a `[GAP]` over interrogating.

## 3. Draft loudly provisional
Write `context/canon/<domain>/<doc>.md` with:
- `status: draft` frontmatter + the loud DRAFT banner (below).
- Per-section provenance: end each section with `> _source: <file/answer>_`, or
  `[GAP: needs human input]` if nothing grounded it.
- **No ungrounded sentence without one of those two marks.**

## 4. Approve is a hard human gate
`/approve-canon` **refuses** to promote a doc that still has `[GAP]` markers. On approval it strips
the banner, sets `status: approved` + `last-reviewed: <today>` + `owner`, and lands via PR. This is
the only path from draft to trusted canon. **Brand is the most dangerous domain to bootstrap**
(subjective, low source material) — hold the line hardest there.

## The DRAFT banner (verbatim)
> ⚠️ **DRAFT — Brainforge-generated, not yet approved.** Provisional until a human owner verifies
> and runs `/approve-canon`. Do not treat as authoritative truth.

## Templates
Per-domain starter skeletons live in `templates/`. They are section structure + `[GAP]` prompts
only — the draft phase fills them; it does not invent them. To author a doc with no template,
create the skeleton first (terse, section-clear), then draft.
