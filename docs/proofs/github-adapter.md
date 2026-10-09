# GitHub adapter — proof summary

**Proven live:** 2026-06-29 · **Source system:** a production web-app repo

## What was proven

- The cheap gate (a `git diff` against the last-synced HEAD) correctly detected a real change in a
  real, actively-developed repo via a local clone — no token required.
- Deterministic extraction produced a derived file with provenance, opened as a PR, and merged.
- The full loop was proven twice: once directly against the real repo, and again scaffolded onto a
  throwaway test brain (scaffold → `/add-source` → `/sync repos` → PR → merge → read-it-back).
- Golden rule #1 proven live: re-running the sync against an unchanged HEAD did zero work
  (short-circuited at the cheap gate).

## What the live run hardened

- The adapter was refactored to fill the new `ADAPTER-TEMPLATE.md` skeleton as part of this proof,
  establishing the canonical adapter shape that the Figma, Website, and later Monday and GA adapters
  filled the same way.
