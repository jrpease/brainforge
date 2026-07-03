# Depth-first wizard — proof summary

**Proven live:** 2026-06-30 · **Source system:** a fresh throwaway brain

## What was proven

- On an empty throwaway brain, the wizard's guard refused to run outside a brain, and the status
  ladder correctly read all 5 domains as `not-started`.
- The eng fast-win was taken end-to-end against a real local repo clone: conventions canon drafted
  from the repo, the approve gate **refused** on a seeded `[GAP]`, an interview turn filled it, the
  repo was wired as a source, a first full sync ran, and the resulting derived file was read back.
- Resumability was proven live with no dedicated state file: re-running the wizard recomputed the eng
  domain as `complete` purely by inspecting brain state (canon frontmatter, sources, sync state), and
  correctly offered the next domain.

## What the live run hardened

- A final-review finding caught a dangling pointer to a nonexistent table; the wizard method doc was
  corrected to point at the real domain catalog, which lives in the brain's canon README rather than
  a top-level table.
- The no-state-file design was validated rather than just asserted: the live re-run confirmed status
  can be derived from brain state alone without a second, driftable source of truth.
