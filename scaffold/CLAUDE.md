# Instructions for LLMs reading this repository

You are reading **{{ORG}}'s shared context repo** — the source of truth for brand, product,
and design. Follow these rules.

## This is READ-ONLY reference

- **Do not create, edit, rename, or delete files in this repo** during normal use.
  Write any output (drafts, ideas, generated artifacts) into the user's *own* workspace
  folder, not here.
- The only time you modify this repo is when the user is explicitly **managing** it
  (setting it up via `/forge`, authoring canon, or running a `/sync...` command from
  `.claude/commands/`).

## Trust model: canon vs. derived

- **`context/canon/`** is human-authored and authoritative. Treat it as fact.
- **`context/derived/`** is auto-generated from upstream sources (Figma, repos, the live
  site). Treat it as a faithful but regenerable snapshot. **Never hand-edit it** — a sync
  will overwrite it. If it seems wrong, the *upstream source* is what to check.
- Each derived doc has frontmatter: `source`, `last-synced`, `generated-by`. Each canon doc
  has `owner`, `last-reviewed`, `status`. Read it.

## When you cite this context

- Cite *where* a fact came from (the canon file, or the derived file + its upstream source).
- If a derived doc's `last-synced` is old, say so — flag possible staleness rather than
  asserting it as current truth.
- If canon and derived appear to **contradict** each other (e.g. canon says the primary color
  is teal, tokens say blue), do not silently pick one. Surface the conflict — it means
  something drifted. (`/drift` reports these.)

## Finding things

- Start at `README.md`, then the per-folder `README.md` files and `_index.md` tables.
- Prefer targeted reads over loading the whole repo into context.

## Don't duplicate canon into other repos

If you're helping in *another* repo (e.g. the web app) and need {{ORG}}'s brand/voice, **link to
this repo's canon — do not copy it in.** See `templates/brain-pointer-snippet.md` for the pointer pattern. One source
of truth, referenced from many places.
