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
    enemy; revisit on a cadence)
  - `status` — `draft` | `approved`
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

(`eng/` and `analytics/` lean derived — their canon is light, e.g. architecture decisions or
metric definitions; most of their content lives in `../derived/`.)
