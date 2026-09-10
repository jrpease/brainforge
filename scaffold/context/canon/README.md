# Canon — human-authored truth ✍️

Everything in this folder is **authored by a human and trusted as fact.** It does not come
from Figma or a repo — it lives in people's heads until someone writes it down here. This is
the heart of the source of truth.

## Rules

- **Edit by hand, via reviewed PR.** Changes to canon get a human review (see
  [CONTRIBUTING.md](../../CONTRIBUTING.md)).
- **Every doc has frontmatter:**
  - `owner` — who is accountable for this being correct
  - `last-reviewed` — date someone last confirmed it's still true (stale-but-trusted is the
    enemy; revisit on a cadence). **Only `/approve-canon` writes it, after a real review** —
    hand-bumping it to silence a nudge destroys the only thing the field is good for.
  - `status` — `draft` | `approved`
  - `review-cadence` — *optional.* How often this doc needs re-confirming:
    `quarterly` · `biannual` · `annual` · `never`. Omit it and `biannual` (180 days) applies;
    declaring a value is a refinement, never a precondition. `never` is the honest opt-out for
    canon that genuinely does not rot — use it deliberately, not to clear a report.

  `/canon-health` reports what is past its cadence, what was approved but never reviewed, and
  what is a stalled draft. A session-start tripwire nudges you to run it.
- **Keep it tight.** Canon is reference an LLM reasons from, not an essay. Bullets and clear
  statements beat prose.

## Authoring (how a doc becomes canon)

**ingest existing material → interview to fill gaps → draft as `status: draft` → owner approves
→ only then is it trusted as `approved`.**

> ⚠️ **Drafted canon is loudly provisional.** Anything not yet promoted to `status: approved` is
> a reviewed first pass, not final-authoritative — a confidently-wrong auto-draft a human
> rubber-stamps is worse than an empty stub. Brand is the most dangerous domain to bootstrap
> (subjective, low source material); the derived-leaning domains are safer.

## What's here

Domains are **à la carte** — only what this brain set up. The out-of-box catalog:

- `brand/` — voice & tone, positioning, messaging, naming, user archetypes
- `product/` — product principles, roadmap
- `design/` — design principles, art direction, packaging, UI/web build standards
- `company/` — mission & values, operating principles, org design

(`eng/` and `analytics/` lean derived — their canon is light, e.g. architecture decisions or
metric definitions; most of their content lives in `../derived/`.)
