# Playbook: drift → draft (the manager-layer flagship)

Reconciles **authored canon against derived reality.** The gap is gold: either canon went stale or the
implementation drifted — and a human should decide which. This playbook closes the loop DESIGN §8 calls
the flagship: **a detected drift becomes a draft canon fix the owner approves** — the same
ingest → draft → approve → PR loop (`authoring/README.md`), initiated by the tool, not remembered by
the user. Run by `/drift`.

## 0. Trigger
Proactively: the `SessionStart` drift gate (`.claude/settings.json`) nudges when `context/canon/` or
`context/derived/` changed since the last review (`.brainforge/last-drift-review`). Or on demand any
time. Good moments: after a big sync, before a campaign, monthly.

## 1. Delta-scope (golden rule #1 — work scales with the delta)
Read the watermark `.brainforge/last-drift-review`. Analyze only the domains whose canon or derived
changed since that commit (`git diff --name-only <sha> HEAD -- context/canon context/derived`). No
watermark (or a domain passed to `/drift`) → check that scope in full.

## 2. Compare — the pattern is always *canon claim* vs *derived fact*
Wire the rows that match the brain's actual domains:

| Canon says… | Derived shows… | Check |
|---|---|---|
| eng conventions' stack/version | synced repo facts (`package.json`, lockfiles) | does canon name the version reality ships? |
| design principles' color/type intent | `design-system/tokens.json` actual values | do the tokens match the stated intent? |
| naming convention / SKU pattern | synced product/SKU codes | do real identifiers follow the convention? |
| messaging taglines / value props | live-site page copy | does the shipped site still say what canon says? |
| product principles' "things we won't do" | shipped repos/pages | did we ship something that violates a principle? |

Analysis is **read-only** — write any long notes to `scratch/`, never to `derived/`.

## 3. Classify — this decides draft vs flag
- **Canon-stale** — derived is a *hard factual reality* (framework/version, count, token value, shipped
  name/route) and canon factually contradicts it. Reality is authoritative; canon simply wasn't
  updated. → **draft the fix** (§4).
- **Implementation-drift or ambiguous** — someone shipped something that violates canon, OR it is
  genuinely unclear which side is wrong (subjective / principle-level intent). → **flag only:** report
  it, recommend the upstream fix, open no draft. **When in doubt, flag.** Brand is held hardest.

## 4. Draft the canon-stale fix (reusing the authoring loop)
For each canon-stale drift the owner accepts, run `/draft-canon` on `<domain>/<doc>` with **the drift
evidence as the ingested material** and the existing approved doc as the skeleton. Inherited guardrails,
none relaxed:
- **Ingest, don't invent** — assert only what the derived fact shows; cite it (`> _source: …_`).
- Anything needing human judgment → `[GAP: needs human input]`, never a guessed sentence.
- Lands `status: draft` + the loud DRAFT banner via PR. **`/approve-canon` is the only path to
  `approved` and refuses on any `[GAP]`.** The tool proposes; the human owns.

## 5. Stamp the watermark (always)
Write `git rev-parse HEAD` into `.brainforge/last-drift-review` and commit that one file, so the
session-start nudge clears until the next canon edit or sync. (Manager-state cursor — commits directly;
drafts go through their own PR.) Merging an approved canon fix later changes canon after this stamp, so
the nudge re-trips once — the next `/drift` re-stamps and it clears. Expected, not a bug.

## Never
- Never **auto-resolve** a drift or mark canon `approved` — the owner decides; `/approve-canon` gates.
- Never draft the **implementation-drift / ambiguous** direction — the tool can't rewrite upstream
  Figma/repos/GA, and guessing which side is right launders fabrication into truth.
- Never hand-edit `.brainforge/last-drift-review` — `/drift` owns it.
