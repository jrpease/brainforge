# Brainforge — roadmap

Guiding principle (inherited from the first production brain): **prove one loop end-to-end
before scaling.** Don't build the wizard, all five domain presets, and five adapters before a
single scaffold→ingest→draft→approve→sync→read-it-back loop works for real.

---

## Phase 0 — Found the repo  ✅

- [x] Lock the design ([`DESIGN.md`](DESIGN.md))
- [x] Create `jrpease/brainforge` (private at the time), founding docs
- [x] **Extraction plan** — reusable spine vs. org-specific content, tagged file-by-file
      lift/generalize/leave. The product seam lands on the `context/` boundary. This was the gate
      to Phase 1.

## Phase 1 — Extract the spine + one domain loop  ✅

- [x] Lift the generalizable scaffold out of the first production brain → [`scaffold/`](scaffold/):
      canon/derived split, `sources.json` schema, `.sync-state.json`, the five golden rules, provenance frontmatter,
      `/sync`-family commands, auto-pull hook, consumer templates. Packaged as a Claude plugin
      ([`.claude-plugin/plugin.json`](.claude-plugin/plugin.json)) from day one.
- [x] `pipeline/ADAPTER-TEMPLATE.md` — the canonical adapter skeleton; built-ins (figma/github/
      website) refactored to fill it; Shopify re-cast as the worked `pipeline/examples/` extension.
- [x] **One built-in adapter, end to end** — the GitHub adapter against a real local repo clone:
      cheap gate → deterministic extract → derived file w/ provenance → PR → merge. Re-run
      short-circuited on an unchanged HEAD (golden rule #1 proven live).
      ([proof](docs/proofs/github-adapter.md))
- [x] Prove the loop against a **throwaway test brain** — scaffolded a brain from `scaffold/`,
      walked scaffold → `/add-source` → `/sync repos` → PR → merge → read-it-back. (The *automated*
      depth-first wizard UX + the canon ingest→draft→approve half are Phase 2.)

## Phase 2 — The wizard + remaining adapters  ✅

- [x] **Depth-first wizard (`/walk`) — proven live.** Domain picker (à la carte) + depth-first
      loop orchestration: guard → status ladder (derived from brain state, **no state file**) →
      fast-win routing (defers brand) → inline loop (scaffold → ingest → draft → approve → wire
      adapter → sync → read-back) → resumable. Ships as the third brain-resident half
      `setup/README.md` + `/walk`, mirroring `pipeline/` and `authoring/`. Proven on a throwaway
      brain: all 5 domains read `not-started` → **eng** fast-win taken end-to-end against a real
      repo (conventions canon drafted from the repo, **approve gate refused** on a seeded `[GAP]`
      until an interview turn filled it, repo wired + first full sync, read it back). Re-running
      `/walk` recomputed **eng `complete`** from brain state alone and offered the next domain.
      ([proof](docs/proofs/depth-first-wizard.md))
- [x] `ingest → interview → draft → approve` canon authoring, with the loudly-provisional guardrail.
      Built as `/draft-canon` + `/approve-canon` → brain-resident `authoring/` method doc + per-domain
      starter templates. Proven end-to-end on a throwaway brain: `brand/positioning` drafted from
      R&D material → approve gate **refused** on a `[GAP]` → interview filled it from
      `brand/archetypes.md` → approved.
- [x] **Figma adapter — proven live** against a real production design-system file. All three
      extraction paths exercised: cheap REST `version` gate (detected a real change), variables
      via the Desktop Bridge (`figma_export_tokens` → DTCG, diffed against baseline = 0 changes),
      styles via REST. The live run hardened the adapter doc twice: (a) `figma_export_tokens`
      natively does the delta write (`strategy: merge`/`dry-run`) and supersedes the old
      Style-Dictionary hop; (b) **a second sanctioned bridge exception** — REST `/components`
      returns the *published-library* snapshot (stale) which diverges from the live document, so
      component-set counts must come from the bridge. Also softened §1 to match the file-level
      state contract (no per-node hashes). ([proof](docs/proofs/figma-adapter.md))
- [x] **Monday adapter — proven live.** Built the Monday built-in (`pipeline/adapters/monday.md`,
      GraphQL-only, one derived file per board, explicit board allowlist) by filling
      `ADAPTER-TEMPLATE.md`, then proved it against a real Monday workspace over
      `MONDAY_API_TOKEN`: cheap gate `boards(ids){updated_at items_count}` → deterministic
      `items_page`/`next_items_page` extract of 4 allowlisted boards → `derived/monday/*` +
      `_index.md`; a re-run short-circuited on unchanged fingerprints (golden rule #1, live).
      Data-faithfulness review re-queried the live API — all four counts matched exactly (no
      fabrication). Second adapter (after Figma) to prove-and-harden — the live run hardened the
      **adapter doc** (two-step `items_page`/`next_items_page` pagination, column-discovery/PII
      pass, `updated_at`-vs-`activity_logs` fingerprint caveat); `ADAPTER-TEMPLATE.md` itself
      needed no change. ([proof](docs/proofs/monday-adapter.md))
- [x] **GA adapter — proven live.** The last Phase-2 adapter and the first **metrics / time-series**
      source (every other adapter is an entity-snapshot). Built `pipeline/adapters/ga.md` by filling
      `ADAPTER-TEMPLATE.md` — GA4 Data API (`runReport`), Core-4 reports, two emit shapes
      (append-merge time series: traffic/ecommerce; refresh-in-full 28d rollups: acquisition/top-pages).
      **The cheap-gate reframe** (the interesting part): a metrics source always "changes," so the gate
      is a date-bounded `sessions`-by-`date` trailing fingerprint `(maxDate, per-day hash)` and the
      delta is the new/restated **date window**, not a stop-if-unchanged hash. Proven live against a
      **real trafficked property**: cold-start 90-day backfill → data-faithfulness review
      **re-queried the live API and matched row-for-row** → a re-run **short-circuited** at the
      cheap gate (zero heavy calls, golden rule #1). Proof summary:
      [`docs/proofs/2026-07-02-ga-live/`](docs/proofs/2026-07-02-ga-live/README.md). **Two spec
      deviations, forced by reality and folded into the hardened adapter:** (a) Google's public GA4
      **demo properties are API-denied** (`429`), so the proof ran against a real user-granted
      property, not the demo; (b) gcloud's **default OAuth client is blocked** from the
      `analytics.readonly` scope and the account's org blocked SA keys/impersonation — the working
      auth was an **own OAuth Desktop client** as yourself (SA key remains the documented
      steady-state where you own the property). Third live hardening pass on the template (the
      **time-series generalization** of §1).
- [ ] ~~Jira built-in~~ → **on-demand only.** It's another entity-snapshot (like Monday), so a
      live proof teaches nothing new. Add via `/add-adapter` when a real Jira source exists — the
      exact case that path (proven with Shopify) is for.
- [x] **`/add-adapter` scaffolder — proven live.** Re-added **Shopify to a real production brain**
      via the documented extension path: dropped in `/add-adapter` + `ADAPTER-TEMPLATE.md` (minimal
      capability drop-in — that brain ran an older runtime), produced `pipeline/adapters/shopify.md`
      (superseding the legacy flat `sync-shopify.md` + repointing `/sync` dispatch), and ran a live
      sync that refreshed `derived/shopify/*` (superseding an earlier bootstrap); a re-run
      **short-circuited** on the unchanged fingerprint (golden rule #1, live). Four findings
      hardened the scaffold (dispatch reconciliation + whole-brain ref scan; auth-revocation
      reality; anti-fabrication counts). **Caveat:** the target's Admin REST token was **revoked**
      (Shopify killed legacy custom-app tokens 2026-01-01) — the sync ran over the sanctioned
      Shopify **MCP** fallback, so REST *steady-state* is proven-in-doc but not proven-live;
      follow-up = mint a new token (Dev Dashboard OAuth token-exchange). Also the first real data
      point for Phase 3's re-emittable runtime-upgrade path (dropping a command + template into an
      older brain). See the [walkthrough](docs/walkthroughs/shopify-add-adapter.md) for the full
      worked extension.

## Phase 3 — Manager / day-2

- [x] **Drift-becomes-a-draft-prompt (flagship) — proven live.** Session-start cheap gate (dependency-free `git`/`cat`/`find`/`test` hook, watermark `.brainforge/last-drift-review`) nudges when canon/derived changed since the last review; `/drift` delta-scopes, classifies (canon-stale → `status: draft` canon fix via the existing `/draft-canon`→`/approve-canon` loop; impl-drift/ambiguous → flag only), and stamps the watermark. Proven on a throwaway brain: never-reviewed nudge → canon-stale (Next.js 13→15) drafted faithfully with `[GAP]` for judgment → `/approve-canon` refused on the `[GAP]` then promoted → impl-drift (pre-consent tracking) flagged, no draft → watermark cleared the nudge and a new derived change re-fired it (golden rule #1, live).
- [x] **Proactive sync-health gate — proven live.** A third dependency-free `SessionStart` tripwire
      (grep only, no jq) nudges to run `/sync-health` when a source is **wired but never synced**
      (`.sync-state.json` has a populated fingerprint slot while `lastFullSync` is `null`) or a derived
      doc still carries `source: TODO`. **Dumb hook, smart command:** it catches the common broken
      states cheaply and defers per-source accounting (and cadence-staleness) to the existing
      `/sync-health`. **Stateless** — no watermark; it reads live state and self-clears on *resolution*
      (unlike the drift gate, which clears on *acknowledgment*). Keys off `.sync-state.json` (not
      `sources.json`, whose `$examples` block would false-positive a fresh brain). Fails silent on
      missing/malformed files. Bump path touched → **v0.3.0** (corollary rule), so every existing brain
      picks it up via `/upgrade`. Proven on a throwaway brain: fresh → silent; `/add-source` (wired,
      unsynced) → nudge; completed `/sync` → clears; `source: TODO` → nudge then clears; corrupt/missing
      state → silent.
- [x] **Re-emittable runtime upgrade path (`/upgrade`) — proven live both ways.** Builder-side command (`commands/upgrade.md`, the first builder-layer file) reads the seam from `plugin.json`'s `runtime.bump`/`once` globs (never hardcoded), short-circuits on `runtime-version == V` (golden rule #1), then classifies every bump-glob file with a deterministic embedded script (zero LLM judgment in the write path): clean → overwrite, modified → flag with baseline kept, consumer-added → never touch, superseded → delete-if-clean, manifest-less brain → conservative adoption pass (byte-match exception adopts provably-stock files). Baseline is a per-file hash manifest (`.brainforge/runtime-manifest.json`, sha256 of *emitted* — post-`{{ORG}}` — content); emit = copy + template, never raw; always lands as `upgrade/runtime-<V>` + PR, never a direct write. Seam gap fixed (`.brainforge/README.md` → bump) + v0.2.0 per the new corollary rule (bump-path change ⇒ version bump). Steady-state proven on a throwaway brain: all five set-logic rows (overwrite/flag-modified/list-consumer/delete-superseded/add), flagged baseline survives, and the `UP-TO-DATE` short-circuit fired. Adoption proven on a real production brain: adds-only branch diff (mechanical proof nothing pre-existing was touched), real ref-scan hits into an older flat `sync-*` era, landed via PR.

## Phase 4 — Package as B (OSS-shaped)

- [x] **Stranger-facing docs.** README and DESIGN generalized for a stranger audience, root
      `CONTRIBUTING.md`, anonymized per-adapter proofs under `docs/proofs/`, and the Shopify
      `/add-adapter` [walkthrough](docs/walkthroughs/shopify-add-adapter.md).
- [x] **`/brainforge:walk` bootstrap.** Live install testing surfaced a fresh-install bootstrap
      gap — the installed plugin exposed only `/upgrade`, no path to a first brain — fixed
      mid-phase (user-approved) with a new builder command `commands/walk.md` (`/brainforge:walk`):
      emits the scaffold + birth manifest via `upgrade.md`'s documented bootstrap script, then hands
      off to the brain-resident `/walk`. Proven live on a scratch brain: 41/41 files emitted, all
      `ADOPT-CLEAN`, manifest 0.3.0/23 files, `{{ORG}}` fully templated. Quickstart corrected to the
      namespaced `/brainforge:walk` (plugin commands are namespaced; bare `/walk` only resolves once
      inside a scaffolded brain).
- [x] **Public, installable distribution.** `jrpease/brainforge` is public and is the marketplace
      source: `claude plugin marketplace add jrpease/brainforge`, then install. Development briefly
      ran in a separate private repo that fed this one; that split is retired, and this repo is the
      single home.

## Phase 5 — Subscribe & route

The consumer question — *how does a large org actually **use** a brain?* — answered as a
**three-layer split** ([`DESIGN.md`](DESIGN.md) §§9–14): the brain carries data + maintenance
behavior, **synapse** carries consumption behavior. Consequence: routing improvements reach every
subscriber via an ordinary plugin update, with zero brain-owner action. (12 tasks, executed
subagent-driven; 6 defects caught in task reviews, 2 more by the eval suite, 3 by the final
whole-branch review.)

- [x] **Manifest + kinds — v0.4.0.** `scaffold/.brainforge/gen-manifest.sh` is a deterministic,
      dependency-free generator: it emits `.brainforge/brain-manifest.json` — every domain with
      `kinds:`, measured tokens, and a precomputed `cheap`/`normal`/`expensive` band — and
      regenerates on every `/sync` and `/approve-canon`, so staleness is the exception, not the
      norm. **Its output formatting is a parsing CONTRACT** for downstream `sed`/`awk` consumers:
      never reformat it without a version bump. The **kinds vocabulary** (23 kinds,
      [`DESIGN.md`](DESIGN.md) §10) is the domain catalog one level down — `/forge` stamps `kinds:`
      at domain creation, adapters leave a destination's `kinds:` as they find it, and `/sync` runs
      classify-and-confirm for unclassified domains. A brain declares what its folders **are**,
      never how to route them.
- [x] **Sixth golden rule — *extraction produces reference, not mirrors*.** Size envelopes live in
      [`scaffold/pipeline/ADAPTER-TEMPLATE.md`](scaffold/pipeline/ADAPTER-TEMPLATE.md); a derived doc
      that lands over its envelope, or has grown 3× since the last sync, gets flagged in the sync PR
      body.
- [x] **`/walk` → `/forge` (both layers) + `/upgrade` learns removals.** The only command rename in
      the wave ([`DESIGN.md`](DESIGN.md) §14); `/upgrade` gained `runtime.remove` plus a hand-edit
      checklist for once-owned docs that still name a removed command. Historical Phase 2/4 entries
      above keep the old name on purpose — they record what shipped at the time.
- [x] **synapse — the shared reader (0.1.0 → 0.2.0), second plugin in the marketplace.** The
      SessionStart hook clones/pulls every subscribed brain (`SYNAPSE_BRAINS`, comma-separated) into
      `~/.synapse/`, renders a ~300-token map (domains, kinds, bands, freshness), is collision-safe
      for same-basename brains, and is **never silently ungrounded** — every failure is a loud
      one-liner. The `brain-routing` skill routes intent → kinds (central table,
      `synapse/routing/intents.json`) → band-gated reads (expensive domains: `_index.md` first, never
      whole-domain) → an announce line (`🧠 loaded: … · skipped: …`). `/synapse:subscribe
      <brain-git-url>` (synapse v0.2.0) does a deterministic settings merge — multi-brain, dedup,
      refuses to touch unparseable settings, warns (never fails) on inaccessible brains.
- [x] **Share rung — v0.5.0.** §3a of the `/forge` walk: after each domain read-back, if the brain
      has a remote, `/forge` prints the team subscription handout with the real URL substituted and
      offers (idempotently) to write it into the brain's `README.md`.
- [x] **Tier-1 and tier-2 pointers.** The org rollout is three lines (tier 2 — the chosen path for
      a git-equipped org): `claude plugin marketplace add jrpease/brainforge` →
      `claude plugin install synapse@brainforge` → `/synapse:subscribe <brain-git-url>`, then restart
      the session. Tier 1 = committed repo settings (`synapse/templates/product-repo-settings.md`);
      tier-2-for-other-tools = `scaffold/templates/brain-pointer-snippet.md` (Cursor/Codex/Copilot).
- [x] **Routing eval suite — 5/5 with-arm, 15/15 runs (~$23), measured at synapse 0.2.0.** Five
      cases against the synthetic `evals/fixtures/acme-brain`. No full `claude plugin eval` run
      since: the harness is gated behind org-level early access, so later changes were checked one
      case at a time with `synapse/evals/routing-smoke.sh` (one run per case, no ablation arm), and
      the suite has since grown to ten cases. The suite caught two real routing defects pre-ship
      (fixture-scavenging when ungrounded, tracker over-fetch). **Any `intents.json` change must
      re-run the routing evals** (`claude plugin eval synapse`, or `routing-smoke.sh` without the
      harness) — budget ~$15–25 per full run, don't run it casually, and budget
      it into the *day*: a long background run plus machine sleep once orphaned a subagent for ~8h
      (fix pattern: independent process watch on the pid + foreground reruns).
- [ ] **MCP façade** (tier 3 — ChatGPT web, Claude.ai) — **next**, own spec. A thin read-only reader
      over the same manifest; routing is data, so there is nothing to redesign. Deliberately after
      the routing table has absorbed a few weeks of announce-line feedback.

Backfill owed before this phase is real in production: brains scaffolded before v0.4.0 have no
manifest yet — per brain, `/upgrade` (brings `gen-manifest.sh` + `/forge`) then `/sync`
(classify-and-confirm proposes `kinds:` for every domain; a human confirms). Expect the rule-6 flag
on the first production brain's synced task-board doc (~30k tokens, 48% of that brain) — the
deferred "a brain is not a project tracker" scope decision, presenting itself.

## Phase 6: Canon day-2  ✅

- [x] **A staleness signal for authored canon (`/canon-health`).** `DESIGN.md` §8 promised
      staleness surfaced from `last-reviewed` age as one-line nudges and nothing had ever read
      that field. `/drift` compares canon against derived and `/sync-health` covers derived only,
      so `brand` — the subjective domain with no derived counterpart, the one DESIGN §4a singles
      out as the most dangerous to bootstrap — had no staleness signal of any kind. A doc could
      sit `status: approved` and wrong indefinitely with nothing to say so. Shipped as
      `.brainforge/canon-health.sh` (deterministic, two modes), `/canon-health`, and a fourth
      session-start tripwire. Threshold is a shipped `biannual` default with a per-doc
      `review-cadence:` override (`quarterly` · `biannual` · `annual` · `never`), following the
      `pipeline/README.md` Defaults precedent: a default always applies, declaring a value is a
      refinement. Reports three states separately — never-reviewed (worst: full authority on a
      template default), past-review, and stalled drafts — and the command explicitly refuses to
      hand-bump `last-reviewed` or propose `never` to reach a clean run, since either turns the
      signal into theatre.

## Field hardening (v0.11.0 – v0.13.0)  ✅

- [x] **Backlog remediation — v0.11.0.** Cleared all 17 open issues in one release
      ([spec](docs/specs/2026-09-11-backlog-remediation.md)): a per-source `synced` flag so
      one never-synced source shows in a brain whose others have synced, `_index.md` size limits
      enforced from the manifest, `/upgrade` catching bump-path changes shipped without a version
      bump, a manifest generator that escapes every string and refuses to write invalid JSON, and
      a no-em-dash rule for public docs (with a test). The rule and its test were retired in v0.14.0
      when the repos merged ([one-repo spec](docs/specs/2026-10-07-one-repo.md) D7).
- [x] **Adapters honour `into:` — v0.12.0.** Every adapter hardcoded its own folder and stamped
      its own `kinds:`, so a brain that moved docs into a new domain would have had them written
      back and re-tagged on the next sync. A sync now writes where the entry says or does not run,
      and routing belongs to the domain ([spec](docs/specs/2026-09-14-adapters-honour-into.md)).
- [x] **`/upgrade` refuses stale checkouts — v0.12.1.** A marketplace clone nothing auto-pulls
      said "up to date" to a brain two versions behind. "Up to date" now prints only from a
      checkout proven current, and a reconciled file can have its baseline moved forward
      ([spec](docs/specs/2026-09-14-upgrade-stale-checkout-rebaseline.md)).
- [x] **Second backlog sweep — v0.12.2.** `/upgrade` counts a bump file deleted upstream without
      a bump as drift; the sync-health tripwire matches only a slot's own `synced` flag; the smoke
      eval lets the reader open `intents.json`, so a pass now proves the intent map routed it; and
      launch-email checks the voice canon's actual rule (never "users") instead of the word
      "customers".
- [x] **Post-merge manifest regeneration in CI — v0.13.0, proven live.** Two PRs that both
      regenerate the map always conflicted on it, and whichever side a merge kept left a
      fingerprint matching neither tree, so every subscriber saw "map predates the current
      content". Brains now ship `.github/workflows/brainforge-manifest.yml`, which runs
      `.brainforge/regen-if-stale.sh` after each push to the default branch: nothing when the map
      is current, one bot commit when it is stale, one standing PR when the branch is protected,
      and a red run (never a quiet one) when it cannot produce a map the reader will accept.
      Proven on a throwaway GitHub repo across direct pushes, a real manifest merge conflict and a
      protected branch ([spec](docs/specs/2026-09-29-ci-manifest-regeneration.md) ·
      [proof](docs/proofs/ci-manifest-regeneration.md)).

## Phase D: executable sync checks (v0.15.0)

Answers a critique of the sync layer: correctness is unverifiable while the cheap gates and the
golden-rule-6 envelope arithmetic are model-run prose. Gates and the envelope check become
scripts with offline tests, session hooks move into `.brainforge/session-start.sh`, and routing
evals gain a subscribed-reader path and cases for the uncovered intents
([spec](docs/specs/2026-10-07-executable-sync-checks.md)).

Live checks, backlogged until they can run against real sources (each gets a proof file in
`docs/proofs/`):

- [ ] **L1 Monday:** in-place column edit bumps `updated_at`; `activity_logs(limit:1)` returns the
      newest event; `created_at` is stable; query cost is acceptable; an immediate re-run reports
      `unchanged`.
- [ ] **L2 every gate:** one live run per built-in returns `unchanged` on an unchanged source, and
      the fingerprint equals what the adapter stored.
- [ ] **L3 GA:** `gcloud auth application-default print-access-token` works with `runReport` on both
      the own-OAuth-client ADC and a service-account key.
- [ ] **L4 session hooks:** a real session in an upgraded brain prints the same nudges as before,
      and the legacy detector fires on a brain holding both old and new hooks.

## Deferred (C-tier and additive)

- MCP universal reader · access tiers · autonomous scheduled sync · declarative/executable adapters.

- **Source-side sync trigger.** A source repo runs a GitHub Action that opens a sync issue on the
  brain when in-scope paths change, so the pull stops depending on one laptop noticing. Cheaper
  than the autonomous scheduled sync above, and it unpicks a coupling worth losing: today a
  source's freshness depends on a clone path on one machine (`git -C <clone>`). Raised by a
  subscribing team in the 2026-09-08 audit and worth taking. Undesigned: cross-repo issue-open
  auth, and it needs a live proof before it ships (CONTRIBUTING's adapter bar).

- **Federation — unit brains alongside the company brain.** `SYNAPSE_BRAINS` already takes a list,
  `brain-routing` already handles a brain being the working directory, and as of v0.9.0 the context
  root is configurable, so a repo whose docs do not live under `context/` can emit a valid
  manifest. What is left is the decision, not the code. A team has volunteered as the pilot: they
  add `_index.md` files with `kinds:` across `docs/`, emit their own manifest, and company canon
  holds a pointer to them for their own facts instead of a hand-curated copy that can only rot —
  which is exactly what happened, brand canon carrying a second-hand description of that team that
  contradicted the team's own canon, under `status: approved`, for three weeks. The thing to think
  hardest about before saying yes: federation makes "which brain owns this fact" a runtime question
  rather than a curation-time one. Probably the right trade. Still a real one. Not now, not never.
