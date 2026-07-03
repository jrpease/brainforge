---
description: Register a new upstream source (Figma file, repo, or website) in sources.json.
---

Add a new watched source of an **existing adapter type**. **Arguments:** `$ARGUMENTS` (e.g. a
Figma URL, a `github.com/org/repo`, or a site URL).

> Adding a *new kind* of source (one with no adapter in `pipeline/adapters/`)? Use `/add-adapter`
> instead — it scaffolds the playbook first, then registers the source.

Steps:
1. Detect the source type from the argument (Figma / repo / website / other built-in).
2. Ask the user for anything missing (label, what to extract, target `into:` folder, cadence).
3. Append a well-formed entry to the correct array in `sources.json` with `enabled: true`.
4. Add an empty fingerprint slot in `.sync-state.json` so the first sync does a full extract.
5. Remind the user which credential (e.g. `FIGMA_TOKEN` / `GITHUB_TOKEN`) must be in `.env`.
6. Offer to run `/sync <that source>` now to do the initial extraction.

Do not commit credentials. Do not put tokens in `sources.json`.
