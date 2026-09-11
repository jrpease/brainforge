# Brainforge: roadmap

Guiding principle: **prove one loop end-to-end before scaling.** Don't build the wizard, all
five domain presets, and five adapters before a single scaffold→ingest→draft→approve→sync→
read-it-back loop works for real.

---

## Phase 0: Found the repo  ✅

- [x] Lock the design ([`DESIGN.md`](DESIGN.md))
- [x] Create the repo (private at the time), founding docs
- [x] **Extraction plan**: reusable spine vs. org-specific content, tagged file-by-file
      lift/generalize/leave. The product seam lands on the `context/` boundary. This was the
      gate to Phase 1.

## Phase 1: Extract the spine + one domain loop  ✅

- [x] Lift the generalizable scaffold into [`scaffold/`](scaffold/): canon/derived split,
      `sources.json` schema, `.sync-state.json`, the five golden rules, provenance
      frontmatter, `/sync`-family commands, auto-pull hook, consumer templates. Packaged as a
      Claude plugin ([`.claude-plugin/plugin.json`](.claude-plugin/plugin.json)) from day one.
- [x] `pipeline/ADAPTER-TEMPLATE.md`: the canonical adapter skeleton; built-ins (figma/github/
      website) refactored to fill it; Shopify re-cast as the worked `pipeline/examples/`
      extension.
- [x] **One built-in adapter, end to end**: the GitHub adapter, proven live: cheap gate →
      deterministic extract → derived file w/ provenance → PR → merge. Re-run short-circuited
      on an unchanged HEAD (golden rule #1 proven live). ([proof](docs/proofs/github-adapter.md))
- [x] Prove the loop against a throwaway test brain: scaffolded a brain from `scaffold/`,
      walked scaffold → `/add-source` → `/sync repos` → PR → merge → read-it-back. (The
      *automated* depth-first wizard UX + the canon ingest→draft→approve half are Phase 2.)

## Phase 2: The wizard + remaining adapters  ✅

- [x] **Depth-first wizard (`/walk`, since renamed `/forge`): proven live.** Domain picker (à la
      carte) + depth-first loop orchestration: guard → status ladder (derived from brain state,
      **no state file**) → fast-win routing (defers brand) → inline loop (scaffold → ingest →
      draft → approve → wire adapter → sync → read-back) → resumable. Ships as the third
      brain-resident half `setup/README.md` + `/walk`, mirroring `pipeline/` and `authoring/`.
      Proven on a throwaway brain: all 5 domains read `not-started` → a fast-win domain taken
      end-to-end against a real repo (conventions canon drafted from source, **approve gate
      refused** on a seeded `[GAP]` until an interview turn filled it, repo wired + first full
      sync, read it back). Re-running `/walk` recomputed that domain as `complete` from brain
      state alone and offered the next domain. ([proof](docs/proofs/depth-first-wizard.md))
- [x] `ingest → interview → draft → approve` canon authoring, with the loudly-provisional
      guardrail. Built as `/draft-canon` + `/approve-canon` → brain-resident `authoring/` method
      doc + per-domain starter templates. Proven end-to-end on a throwaway brain: a brand canon
      drafted from source material → approve gate **refused** on a `[GAP]` → interview filled it
      → approved.
- [x] **Figma adapter: proven live** against a real production design-system file. All three
      extraction paths exercised: cheap REST `version` gate (detected a real change), variables
      via the Desktop Bridge (native delta-write export, diffed against baseline = 0 changes),
      styles via REST. The live run hardened the adapter doc twice: (a) the bridge export
      natively does the delta write and supersedes an older Style-Dictionary hop; (b) **a second
      sanctioned bridge exception**: the REST components endpoint returns a stale
      published-library snapshot that diverges from the live document, so component-set counts
      must come from the bridge. Also softened the state contract to match file-level (not
      per-node) hashing. ([proof](docs/proofs/figma-adapter.md))
- [x] **Monday adapter: proven live.** Built the Monday built-in (GraphQL-only, one derived
      file per board, explicit board allowlist) by filling `ADAPTER-TEMPLATE.md`, then proved it
      against a real Monday workspace: cheap gate → deterministic paginated extract of 4
      allowlisted boards → derived files + index; a re-run short-circuited on unchanged
      fingerprints (golden rule #1, live). A data-faithfulness review re-queried the live API:
      all counts matched exactly (no fabrication). Second adapter (after Figma) to
      prove-and-harden: the live run hardened the **adapter doc** (two-step pagination,
      column-discovery/PII pass, fingerprint caveat); the template itself needed no change.
      ([proof](docs/proofs/monday-adapter.md))
- [x] **GA adapter: proven live.** The last Phase-2 adapter and the first **metrics /
      time-series** source (every other adapter is an entity-snapshot). Built by filling
      `ADAPTER-TEMPLATE.md`: GA4 Data API (`runReport`), Core-4 reports, two emit shapes
      (append-merge time series vs. refresh-in-full rollups). **The cheap-gate reframe** (the
      interesting part): a metrics source always "changes," so the gate is a date-bounded
      trailing fingerprint and the delta is the new/restated **date window**, not a
      stop-if-unchanged hash. Proven live against a real trafficked property: cold-start backfill
      → data-faithfulness review re-queried the live API and matched row-for-row → a re-run
      **short-circuited** at the cheap gate (zero heavy calls, golden rule #1). Two spec
      deviations, forced by reality and folded into the hardened adapter: public demo properties
      turned out to be API-denied, and default OAuth tooling was blocked from the required scope
      in this environment, so the proof ran against a real user-granted property with a
      purpose-built OAuth client. Third live hardening pass on the template (the time-series
      generalization). Anonymized proof artifact:
      [`docs/proofs/2026-07-02-ga-live/`](docs/proofs/2026-07-02-ga-live/README.md).
- [ ] ~~Jira built-in~~ → **on-demand only.** It's another entity-snapshot (like Monday), so a
      live proof teaches nothing new. Add via `/add-adapter` when a real Jira source exists,
      the exact case that path (proven with Shopify) is for.
- [x] **`/add-adapter` scaffolder: proven live.** Re-added Shopify to a real production brain
      via the documented extension path: dropped in `/add-adapter` + `ADAPTER-TEMPLATE.md`
      (minimal capability drop-in against an older runtime), produced a filled-in adapter doc
      (superseding a legacy flat sync doc + repointing `/sync` dispatch), and ran a live sync
      that refreshed the derived output; a re-run **short-circuited** on the unchanged
      fingerprint (golden rule #1, live). Four findings hardened the scaffold (dispatch
      reconciliation + whole-brain ref scan; auth-revocation reality; anti-fabrication counts).
      **Caveat:** the target's REST token was revoked (the platform killed legacy custom-app
      tokens), so the sync ran over the sanctioned MCP fallback: REST *steady-state* is
      proven-in-doc but not proven-live; follow-up is minting a new token. Also the first real
      data point for Phase 3's re-emittable runtime-upgrade path (dropping a command + template
      into an older brain). See the [Shopify add-adapter walkthrough](docs/walkthroughs/shopify-add-adapter.md)
      for the full worked extension.

## Phase 3: Manager / day-2  ✅

- [x] **Drift-becomes-a-draft-prompt (flagship): proven live.** Session-start cheap gate
      (dependency-free hook, watermark file) nudges when canon/derived changed since the last
      review; `/drift` delta-scopes, classifies (canon-stale → `status: draft` canon fix via the
      existing `/draft-canon`→`/approve-canon` loop; impl-drift/ambiguous → flag only), and
      stamps the watermark. Proven on a throwaway brain: never-reviewed nudge → canon-stale
      change drafted faithfully with a `[GAP]` for judgment → approve gate **refused** on the
      `[GAP]` then promoted → impl-drift flagged with no draft → watermark cleared the nudge and
      a new derived change re-fired it (golden rule #1, live).
- [x] **Proactive sync-health gate: proven live.** A third dependency-free session-start
      tripwire nudges to run `/sync-health` when a source is wired but never synced, or a
      derived doc still carries a placeholder `source`. **Dumb hook, smart command:** it catches
      the common broken states cheaply and defers per-source accounting to the existing
      `/sync-health`. **Stateless**: no watermark; it reads live state and self-clears on
      *resolution* (unlike the drift gate, which clears on *acknowledgment*). Proven on a
      throwaway brain: fresh → silent; new source wired-but-unsynced → nudge; completed sync →
      clears; placeholder source → nudge then clears; corrupt/missing state → silent.
- [x] **Re-emittable runtime upgrade path (`/upgrade`): proven live both ways.** Builder-side
      command reads the seam from the plugin manifest's bump/once globs (never hardcoded),
      short-circuits when already current (golden rule #1), then classifies every bump-glob file
      with a deterministic embedded script (zero LLM judgment in the write path): clean →
      overwrite, modified → flag with baseline kept, consumer-added → never touch, superseded →
      delete-if-clean, manifest-less brain → conservative adoption pass. Baseline is a per-file
      hash manifest of *emitted* (post-template) content; emit is always copy + template, never
      raw; always lands as a PR, never a direct write. Steady-state proven on a throwaway brain:
      all five set-logic rows, flagged baseline survives, and the up-to-date short-circuit
      fired. Adoption proven on a real production brain: adds-only branch diff (mechanical proof
      nothing pre-existing was touched), real ref-scan hits into an older era, landed via PR.

## Phase 4: Package as B (OSS-shaped)

- [x] **Publish seam + `/publish` command.** An allowlist manifest in the plugin manifest
      (`include` globs, authored-public-variant `map`) plus a deterministic `/publish` command:
      assemble → audit → diff → land as a PR into the public staging repo. The leak denylist
      lives in a private `publish-audit.json` at the repo root, matched by no include glob, so
      it never ships with the set it polices. Zero LLM judgment in the write path: what's
      public is auditable code, not memory.
- [x] **Authored public docs set.** This README and DESIGN.md generalize the private originals
      for a stranger audience, alongside a contribution guide, the Shopify extension walkthrough,
      and a per-adapter proof-summary set, all shipped.
- [x] **Live-proof matrix**: all seven rows proven, the adapter and wizard proofs re-run
      against a clean local harness, then live against the real staging repo, confirming the
      publishable set is self-sufficient outside the private working repo.
- [x] **`/brainforge:walk` bootstrap.** Fresh-install → first brain: emit the scaffold and a
      birth manifest, then hand off to the brain-resident wizard. Added and proven live during
      this phase.
- [x] **Staging repo + installable distribution.** The public staging repo is stood up, the
      first real `/publish` PR landed, and installability proven end to end: the publishable set
      works as a plugin outside the private working repo. Public availability is the distribution
      path this phase was built to reach, reached deliberately rather than as a default of shipping
      the seam.

## Phase 5: Subscribe & route

- [x] **Manifest + kinds.** Schema and tooling for describing the brain's shape: domain kinds,
      routing rules, and what each kind costs at read time.
- [x] **Synapse reader.** Consume the manifest in a Claude Code plugin and in template snippets
      for other tools. Route prompts to only the slice they need. ~300-token map; announcing what
      it loaded and skipped.
- [x] **Tier-2 pointer.** Extensible snippet templates for Cursor, Codex, and any file-aware
      tool to paste into their rule files: same manifest, same reading rules.
- [x] **Routing evals.** Measure routing signal-to-noise and tool-specific read performance at
      eval time. Seeded cases over all domains prove the tracer + classify + route pipeline
      catches the right slice.
- [ ] **MCP façade**: a read-only endpoint over the same manifest, for web-only tools (ChatGPT, Claude.ai). Next.

## Deferred (C-tier and additive)

- MCP universal reader · access tiers · autonomous scheduled sync · declarative/executable adapters.

- **Source-side sync trigger.** A source repo runs a CI job that opens a sync issue on the brain
  when in-scope paths change, so the pull stops depending on one laptop noticing. Cheaper than the
  autonomous scheduled sync above, and it unpicks a coupling worth losing: today a source's
  freshness depends on a clone path on one machine (`git -C <clone>`). Undesigned: cross-repo
  issue-open auth, and it needs a live proof before it ships (see CONTRIBUTING's adapter bar).

- **Federation: team brains alongside the org brain.** `SYNAPSE_BRAINS` already takes a list,
  `brain-routing` already handles a brain being the working directory, and as of v0.9.0 the
  context root is configurable, so a repo whose docs do not live under `context/` can emit a valid
  manifest. What is left is the decision, not the code: a team keeps its own brain, and org canon
  holds a pointer to it for that team's facts instead of a hand-curated copy that can only rot.
  The thing to think hardest about first: federation makes "which brain owns this fact" a runtime
  question rather than a curation-time one. Probably the right trade. Still a real one.
