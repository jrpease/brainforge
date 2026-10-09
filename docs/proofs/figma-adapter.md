# Figma adapter — proof summary

**Proven live:** 2026-06-29 · **Source system:** a production design-system file

## What was proven

- The cheap REST `version` gate against the live file detected a real version change — the correct
  trigger to extract, not a stale no-op.
- Variables extracted via the Figma Desktop Bridge (`figma_export_tokens`, DTCG format): 215/7
  diffed, zero changes detected.
- Styles extracted via REST: 58/4 diffed.
- Component-set counts were sourced from the bridge, not REST: REST's published-library snapshot
  reported 39 sets / 2076 components (stale, pre-cleanup), while the bridge-derived count against
  the live document was 27 sets — the stable signal.
- A re-verification sync of the same file found no content change to any tracked resource:
  fingerprint re-stamped, component provenance corrected — a re-stamp, not a rewrite.

## What the live run hardened

- `figma_export_tokens` was found to natively perform the delta write (`strategy: merge`/`dry-run`),
  superseding the old export → transform → Style Dictionary hop.
- A second sanctioned bridge exception was established: live component inventory must come from the
  bridge, since REST's `/components` and `/component_sets` return a published-library snapshot that
  can diverge from the live document until a re-publish.
- The state model was softened to match reality: state is tracked at the file level (one
  version/timestamp per source), not per-node — the prior doc's promise of per-node hash diffing
  wasn't backed by the schema.
