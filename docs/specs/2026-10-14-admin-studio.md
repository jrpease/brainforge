# Brainforge Studio: an admin app over a brain

Status: planned
Reviewed: 2026-10-15 — design ready to plan; Plan needs revision, fixes applied the same day
Date: 2026-10-14

## Goal

Today a brain is managed entirely from a terminal: `/sync`, `/draft-canon`, `/drift`, `/upgrade` and
`/add-source` are Claude Code commands, and the state they leave behind (`sources.json`,
`.sync-state.json`, the manifest, canon frontmatter) is only readable as files. Brainforge Studio is
a local web app, Obsidian- or Linear-like, that gives the people who **manage and write into** a brain
one place to see its health, browse it, triage its PRs, edit canon, and launch those runs.

After it ships, an admin runs `npx brainforge-studio` in a brain and gets a cockpit. Every verb is
still a Claude Code run: Studio launches runs and streams them, it does not replace them. The Studio
process itself never writes to the brain. The runs it launches follow each command's own write rules,
which are mostly PRs but not only: `/drift` commits its watermark directly, `/add-source` edits
`sources.json` and `.sync-state.json` in the working tree, and `/sync` updates `.sync-state.json`
before its PR.

## Non-goals

- **Consumers.** People who read the brain keep using the synapse plugin or the MCP server inside
  their own tools, unchanged.
- **A hosted app, an Obsidian plugin, or an auth layer.** It is local. The brain repo's GitHub
  permissions already gate approve and merge; Studio adds no accounts or per-brain access of its own.
- **Studio writing to the brain itself.** Studio's own server code never writes a file in the brain;
  writes happen only inside the Claude runs it launches, under those commands' rules.
- **Changing what a command writes.** Studio does not wrap `/drift` or `/add-source` to force their
  direct writes through a PR.
- **Living inside the brain.** The brain stays zero-dependency markdown, JSON and shell.
- **The design system itself.** It has its own spec,
  `docs/specs/2026-10-14-brainforge-design-system.md`. Studio uses it; this spec does not define it.

## Decisions

The unnumbered first row and rows 1–5 were settled by Jordan in a brainstorm held in the throughline
session on 2026-10-14 and handed here. The rest were settled in a grilling on 2026-10-14, where Jordan accepted the stated
recommendation unless the row says otherwise. Rows marked *(review)* came from the 2026-10-14
and 2026-10-15 reviews, whose recommended fixes Jordan accepted. Rows marked *(standing)* were open
questions the v0 plan needed answered; they take the recommendation under Jordan's standing
instruction for this work ("take your recommendations when you have a question; only pull me in for
an important P0"), given 2026-10-14. Any of them can be reopened.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Audience and form | Admins who manage and write into the brain; a **local web app** | Admins need a cockpit; consumers are already served in their own harnesses | An Obsidian plugin; a hosted app; an auth layer |
| 1. Prerequisites | Admins already have Claude Code and git (and `gh`, row "GitHub"; and `python3`, row "Health: gate prerequisites"). Studio runs the installed Claude Code headless, and shows a setup screen naming whichever is missing | Every brain verb is a Claude Code run already; Studio is the cockpit, not a reimplementation | Studio bundling a model client or an API key |
| 2. Brains per window | One brain per window; a switcher later (`/subscribe` already keeps a list) | Keeps v0 simple | Multi-brain views in v0 |
| 3. Writing canon | Both ways: a direct editor with frontmatter as fields, and a "Draft with Claude" panel that runs `/draft-canon`. Every canon save lands as a PR; Approve runs the `/approve-canon` gate (which phase each half lands in, and how the editor opens its PR, are open: see "What action means for v1" and "The two approves") | Golden rule for canon: nothing writes directly. The PR is the unit of work | Saving canon to the working tree; an approve that skips the `[GAP]` gate |
| 4. Where the code lives | `studio/` in the brainforge repo, published to npm, started with `npx`. Never inside the brain. The repo's first `package.json`, so it gets its own CI lane | The brain stays zero-dependency; one repo since v0.14 | A separate repo; files emitted into brains |
| 5. Phasing | **v0** read-only: Health, a Brain browser built from the manifest, and a Sources list (row "Sources in v0"). **v1**: the Inbox (the brain's PRs, Linear-style triage) and the canon editor. **v2**: actions run through headless Claude Code | Read-only first proves the readers before anything can change a brain | Actions in v0 |
| Write rule *(review)* | The Studio process never writes to the brain. Claude runs it launches follow their command's own rules, including `/drift`'s direct watermark commit and `/add-source`'s working-tree edits | That is what the commands do today; promising "everything is a PR" would be false for three verbs | Refusing to launch `/drift` or `/add-source`; rewriting those commands for Studio |
| Stack | Vite + React for the UI, a small Hono server on Node, one package | Fast `npx` start; the design system's tokens drop in as CSS variables; no server rendering needed locally | Next.js; Svelte or web components |
| How runs stream | Spawn the installed `claude` with `-p --output-format stream-json --include-partial-messages`, with the brain as its working directory, and forward the events to the browser | Uses the admin's own login, settings, plugins, and the brain's `.claude/commands/`; no API key | The Claude Agent SDK inside the server |
| GitHub | Through the admin's `gh` login, by running `gh`. `gh` joins the setup screen's prerequisites | No OAuth app, no stored token; GitHub permissions stay the only access control | A GitHub OAuth app; a pasted personal token |
| Name | **Brainforge Studio**, npm package `brainforge-studio` (free on npm on 2026-10-14; `brainforge` is taken by another project), `npx brainforge-studio` | Reads right for an admin cockpit | — |
| Finding the brain | `npx brainforge-studio [path]`, defaulting to the current folder. Refuses with a clear message when the folder is not a brain (no `sources.json` and no `.brainforge/`) | Matches how admins already work, from inside a brain clone | A file picker; reading `SYNAPSE_BRAINS` in v0 |
| Local server security | Listens on `127.0.0.1` only, and requires a random per-launch token that is printed in the URL it opens. From v0 | Without it any web page could call localhost and, from v2, start Claude runs in a brain. Cheap now, painful to retrofit | An open localhost API |
| Health: what v0 shows *(review)* | Only what the brain's own scripts report: canon staleness from `.brainforge/canon-health.sh` (its full report, not `--tripwire`); the drift and sync tripwires from `.brainforge/tripwires.sh` (row "Tripwire script"); upstream changes from the `gate-*.sh` scripts, run on demand by "Check sources now". `.sync-state.json` times are shown as-is, with no fresh/stale verdict. The cadence verdict comes with v2, by running `/sync-health` as a Claude run. Exit codes are read per script: exit 1 from `canon-health.sh` is a finding (stale canon); exit 1 from a gate is an error (misuse or no `python3`) | One source of truth: no script compares last-synced to cadence, because `/sync-health` does that in the model. Studio can never disagree with the brain's scripts if it only shows their output | Recomputing staleness or cadence in TypeScript; a sync-freshness verdict in v0 |
| Health: gate prerequisites *(review)* | The gates need `python3` (each exits 1 without it); `python3` joins the setup screen. Studio runs each gate with the brain as its working directory and never reads `.env`: the gates read their own credentials (`FIGMA_TOKEN`, `MONDAY_API_TOKEN`, GA) from the brain's `.env` themselves. The GitHub gate runs a non-interactive `git fetch` on each source's `localClone`, not `gh`. A missing credential or clone is shown as the gate's own `not-checked` line with its reason | Studio never touches secrets; showing the gate's own status keeps "only what the scripts report" true | Studio reading or passing `.env`; a Studio-side credential check |
| Tripwire script *(review)* | A scaffold change ships with Studio v0: the drift-watermark and sync tripwires move out of `session-start.sh` into `.brainforge/tripwires.sh`, which prints the same lines and does nothing else (no `git pull`, no network, no writes) and always exits 0 (non-zero means the script itself failed, never a finding). `session-start.sh` calls it fail-safe (`[ -r … ] && bash … || true`, as it already calls `canon-health.sh`), so a brain with a kept-local `session-start.sh` never errors. It is a **brainforge plugin release** of its own, separate from Studio's npm clock: the file joins `runtime.bump` in `.claude-plugin/plugin.json`, the plugin version is bumped, and `tests/session-start.test.sh`, `tests/sync-tripwire.test.sh`, `scaffold/.brainforge/README.md` and the `canon-health.sh` header are updated. It lands before or alongside Studio v0. Brains get it on their next `/upgrade`; until then Studio's tripwire panel says "not available in this brain; run `/upgrade`" | `session-start.sh` starts with `git pull --ff-only` on the brain, which would make every Health refresh write to the admin's checkout and could hang on a credential prompt. A pull-free script keeps the write rule true and gives Studio one script to call | Studio running `session-start.sh`; reimplementing the tripwires in TypeScript; dropping the tripwires from v0 |
| CI lane | A separate `studio.yml`, run only when `studio/**` changes: `npm ci`, typecheck, unit tests, build, one browser smoke test, and a warning (never a failure) while `tokens.draft.css` is non-empty (design-system spec). `test.yml` unchanged | The bash suite never needs Node; a Studio change never re-runs the shell tests | Folding Node into `test.yml` |
| Tests *(review)* | Each test builds a temporary brain the way `tests/canon-health.test.sh` does: `scaffold/` (for the scripts) plus the synthetic `evals/fixtures/acme-brain` (for `context/` and the manifest), plus a small synthetic `sources.json` and `.sync-state.json` and canon docs with `last-reviewed` dates relative to today (as `tests/canon-health.test.sh` does) written by the test setup, so stale and never-reviewed cases exist and no assertion flips on a calendar date (the fixture's own approved docs cross their cadence on 2027-01-26), inside a fresh `git init`. Vitest covers the server's readers; one Playwright smoke opens Health and the Brain browser with a clean console | The fixture alone has only `context/` and the manifest, so Health would render as "not available". Building a temp brain needs no change to the fixture | Tests against a real brain; growing the shared fixture for Studio |
| Versioning and release | Studio's own version in `studio/package.json`, separate from the plugin's. Published to npm by hand from a tag; no npm token in CI for now | Its own release clock; a publish token out of CI is out of reach of a compromised workflow | Automated publishing, for now |
| Brain compatibility | Degrade per panel: a missing file (an older brain without `brain-manifest.json`, say) makes that panel say "not available in this brain; run `/upgrade`" and the rest keeps working. Keyed on file presence; the manifest's `"schema"` number exists but nothing here needs it | Panel-by-panel is all a reader needs | Refusing old brains; adding a version stamp to every brain |
| Styling *(review)* | Studio uses the Brainforge design system from its own spec. v0 needs only its tokens (colours, type, spacing, radius, light and dark modes) as CSS custom properties; the Figma side lands on its own clock | Lets Studio v0 start without waiting on Figma | A Studio-only design system |
| UI build process | Jordan's call (2026-10-15): Studio's screens are designed and built with the `product-design` skill | — (Jordan's direction) | Building screens ad hoc, outside that skill |
| Theme switch *(review)* | Studio owns it. Dark is the bare `:root`; light is `[data-theme="light"]`. On load Studio reads a stored choice, else `prefers-color-scheme`, and sets `data-theme` on `<html>`; a header toggle stores the choice per browser | throughline's `vanilla-css` adapter emits `[data-theme]` only and nothing watches the system setting; the brand's dark "void" is the reference | Putting app behaviour in the design system |
| Sources in v0 *(standing)* | A read-only Sources list in v0 (from `sources.json` and `.sync-state.json`); Add Source in v2 | It is Health's other half and only reads files | An empty Sources screen until v2 |
| Node floor *(standing)* | Node 20 or later, in `engines` and checked on the setup screen | Current LTS line; Vite needs 18+ | Supporting Node 18 |
| Fonts *(standing)* | Bundled with the package (`@fontsource` packages for Space Grotesk, Instrument Serif, JetBrains Mono), never loaded from a CDN | A local app should not call out to the internet to render; the brand site's `next/font` loading does not exist in Vite | A Google Fonts link |
| Who it is for *(2026-10-15)* | Any admin who builds a brain with Brainforge, not only Jordan: Studio is a public npm package that works on any Brainforge brain, with the admin's own logins. Discovery is a README section and a pointer at the end of `/brainforge:forge`, shipped after the first npm publish | Jordan markets Brainforge to other admins | A Studio only for Jordan's brains |

## Open questions

- **What "connect" means.** Jordan's original ask was a GUI to "connect, manage, upgrade, sync and
  source" a brain. There is no connect verb: `/subscribe` subscribes a reader to a brain, and
  `/add-source` connects a source to a brain. Recommendation: in Studio, "connect" is `/add-source`
  (the Sources screen) and opening a brain is the `[path]` argument; `/subscribe` stays a consumer
  verb. Unresolved.
- **The supporting screens' phase.** The handoff names Sources (`/add-source`), Runs (a live log of
  agent jobs), Upgrade, and the Brain browser. Only the Brain browser has a phase (v0). Recommendation:
  Runs and Upgrade in v2, since both are actions. (Sources is settled: row "Sources in v0".)
  Unresolved.
- **What "action" means for v1.** The v1 canon editor has to branch, commit and open a PR, and the
  Inbox may approve or merge, yet actions are v2 and the Studio process never writes to the brain.
  Recommendation: "action" in the phasing row means a Claude run; v1 may use `git` and `gh` directly
  for exactly two things, opening a canon-edit PR and reviewing or merging a PR, working in a separate
  `git worktree` so the admin's checkout is never touched. That is a narrow exception to the write
  rule and needs Jordan's yes. v0 does not depend on it; v1 cannot start without it. Unresolved.
- **The two "approve"s.** The Inbox's approve is `gh pr review --approve` (and merge) on an existing
  PR. The canon editor's Approve runs `/approve-canon`, a Claude run that flips `draft` to `approved`
  and opens a *new* PR. Recommendation: name them differently in the UI ("Approve PR" vs "Promote to
  approved"); the second is a Claude run, so v2. Unresolved.
- **Permissions for headless runs.** `claude -p` stalls on a permission prompt nobody can see unless
  the tools a command needs are allowed. Recommendation: rely on the brain's `.claude/settings.json`
  allow-list, and have Studio detect a permission denial in the stream and show it with the missing
  tool named, rather than passing `--permission-mode` to widen access. Decide before v2. Unresolved.

## Facts this rests on (checked 2026-10-14)

- The only server today is `synapse/mcp/server.py`: read-only, stdio-only, standard-library Python.
  There is no HTTP API and no `package.json` in the repo.
- Nothing in ROADMAP or DESIGN mentions a UI; the hosted MCP endpoint is parked (DESIGN.md:39-41,
  ROADMAP.md, Deferred).
- What a UI reads: `sources.json`, `.sync-state.json`, `.brainforge/brain-manifest.json`, canon
  frontmatter (`owner`, `status`, `last-reviewed`, `review-cadence`), `.brainforge/last-drift-review`,
  and the `SYNAPSE_BRAINS` / `SYNAPSE_HOME` environment variables.
- The brain's deterministic checks: `.brainforge/canon-health.sh` (no network, no LLM);
  `.brainforge/gate-{github,figma,website,monday,ga}.sh` (read-only network calls, need `python3`,
  read credentials from the brain's `.env` themselves; `gate-github.sh` uses `git fetch` with
  `GIT_TERMINAL_PROMPT=0` and ssh `BatchMode=yes`);
  and `session-start.sh`, which first runs `git pull --ff-only` on the brain, then prints up to four
  more free-text lines (drift tripwire, sync tripwire, `canon-health.sh --tripwire`, a legacy-settings
  warning). The drift and sync tripwires are inline blocks reading `$CLAUDE_PROJECT_DIR`, not
  separate scripts, and the script has no flag to skip the pull. The sync tripwire only catches never-synced and `TODO`
  sources. `/sync-health` is a Claude command; no script compares last-synced to cadence.
- Commands that write outside a PR: `/drift` step 5 (watermark commit), `/add-source` steps 3–4
  (`sources.json`, `.sync-state.json`), `/sync` step 3 (`.sync-state.json` before the PR).
- `evals/fixtures/acme-brain` holds only `context/` and `.brainforge/brain-manifest.json`, and no
  `sources.json`, `.sync-state.json` or scripts. It has no `.git` of its own but sits inside this
  repo, so a script that walks to the git root from it lands in `brainforge/`; hence a fresh
  `git init` per test. `tests/canon-health.test.sh`
  already builds temp brains from `scaffold/` scripts.
- `claude --help` lists `-p`, `--output-format stream-json` and `--include-partial-messages`.

## Where it diverged

Recorded during the build (Part A and Part B up to the PR):

- **Node versions.** Vite 8 and Vitest 5 need Node 22 to build and test; what admins run (Hono and
  its Node server) needs only Node 20, so the Node 20 floor holds. CI builds and tests on 22 and runs
  the smoke test on 20 (B11).
- **npm.** npm 10.9's resolver crashes on Vitest's optional peers; `studio/.npmrc` sets
  `legacy-peer-deps`. Every dependency is pinned to a version published at least two weeks earlier.
- **Health reads `canon-health.sh`'s text.** The full report has no machine format, so Studio parses
  its stable text and falls back to the raw text if the format changes. A `--json` mode in the script
  would remove that; it is a scaffold change, not done here.
- **Comps.** Two directions for Health were built state-complete; A (Ledger) was first recommended,
  then measured to show less per screen (11 vs 13 action items above the fold), and Jordan picked B
  (Seam) on the corrected numbers. A is kept under `studio/design/comps/`.
- **Type scale.** The draft started at a 13px body; the product-design canon measures 14px, so the
  scale became 12/14/16/20/28 and a full status set (warning, error, success, info) joined `stale`,
  which stays reserved for drifted or out-of-date facts.
- **Light-theme contrast.** The first light palette failed WCAG contrast on muted text; it was
  re-picked by measurement (every text pair ≥ 4.5:1).
- **Markdown.** The Brain browser renders a small, safe subset of markdown (React elements, no raw
  HTML) rather than plain text.
- **Performance floor.** One rule (long frames) fails on this machine even for a blank page; it is
  recorded as not evidenced, and shipping past it is put to Jordan (see `studio/SCREENS.md`).

## Plan

Two parts, two branches, two PRs. Part A is a Brainforge plugin release and lands first. Part B is
Studio v0 and is not published to npm by this plan; the first public release is its own step at the
end, done by Jordan. Baseline before starting: `for t in tests/*.test.sh; do bash "$t" >/dev/null 2>&1 && echo PASS || echo "FAIL $t"; done | sort | uniq -c`
→ `30 PASS` (run 2026-10-15).

### Part A — Brainforge 0.17.0: the pull-free tripwire script (branch `feat/tripwires-script`)

#### Step A1 — Create `tripwires.sh`

Files: `scaffold/.brainforge/tripwires.sh` (new)
Change: A bash script, header comment in the style of `canon-health.sh` (purpose, USAGE, OUTPUT,
EXIT). Usage `tripwires.sh [brain-dir]`; the brain dir is `$1`, else `$CLAUDE_PROJECT_DIR`, else the
parent of the script's own directory. Body: hooks (2) drift gate and (3) sync-health tripwire,
moved verbatim from `session-start.sh:49-57` with `$CLAUDE_PROJECT_DIR` replaced by the resolved
brain dir, each still in its own subshell, wrapped in `main() { … }` and ending `main "$@"; exit 0`.
No `git pull`, no network, no writes. Always exits 0; a non-zero exit means the script itself broke.
Mode 0755.
Verify: `bash -n scaffold/.brainforge/tripwires.sh && grep -cE '^[^#]*git (pull|fetch)' scaffold/.brainforge/tripwires.sh`
→ syntax OK and `0`.

#### Step A2 — `session-start.sh` calls it

Files: `scaffold/.brainforge/session-start.sh`
Change: Replace hooks (2) and (3) (`:49-57`) with one subshell under the comment line
`  # (2)+(3) drift gate and sync-health tripwire, in tripwires.sh`:
`T="$(dirname "${BASH_SOURCE[0]}")/tripwires.sh"; [ -r "$T" ] && bash "$T" "$CLAUDE_PROJECT_DIR" 2>/dev/null || true`.
Resolve it beside the script, not under `$CLAUDE_PROJECT_DIR`: `tests/sync-tripwire.test.sh` runs
the scaffold copy against a brain that holds only `.sync-state.json`. Rewrite header items (2) and
(3) (`:9-21`) to say they live in `tripwires.sh` and why (Studio needs them without the pull).
Hook order and output are unchanged.
Verify: build a tripped brain (derived doc, no watermark, `.sync-state.json` with `"synced": false`,
`git init` + commit) and run `CLAUDE_PROJECT_DIR=<it> bash scaffold/.brainforge/session-start.sh`
→ prints `Context:`, the drift line, `Sync health`, in that order, exit 0. Then
`grep -c 'sync-state.json\|last-drift-review' scaffold/.brainforge/session-start.sh` → only the
legacy detector's `last-drift-review` line remains (1). The test suite goes green in A3.

#### Step A3 — Tests

Files: `tests/session-start.test.sh`, `tests/sync-tripwire.test.sh`, `tests/tripwires.test.sh` (new)
Change:
- `session-start.test.sh` `brain()` (`:18-25`, the `cp` on `:20`) also copies `scaffold/.brainforge/tripwires.sh`; the (e)
  rewrite test's anchor (`:94`) becomes `"  # (2)+(3) drift gate and sync-health tripwire, in tripwires.sh\n"`.
- `sync-tripwire.test.sh:10` greps `sync-state.json` in `tripwires.sh` instead of `session-start.sh`.
- New `tripwires.test.sh`, in the style of the two above: in a temp brain with a fresh `git init`
  and a commit, (a) a brain with derived docs and no watermark prints the "never had a drift review"
  line; (b) an unsynced `.sync-state.json` prints "Sync health"; (c) a clean brain prints nothing;
  (d) every case exits 0; (e) no pull or fetch: run with a stub `git` first on `PATH` that exits 99 and
  logs on `pull`/`fetch` and passes everything else to the real git (as `session-start.test.sh:100-116`
  stubs it), and assert the log is empty and `git status --porcelain` is identical before and after; (f) the brain dir is taken
  from `$1` when given, ignoring `$CLAUDE_PROJECT_DIR`; (g) a `session-start.sh` copied without
  `tripwires.sh` beside it still exits 0 and still prints the pull and canon-health lines.
Verify: `bash tests/session-start.test.sh && bash tests/sync-tripwire.test.sh && bash tests/tripwires.test.sh`
→ three PASS.

#### Step A4 — Docs and manifest

Files: `scaffold/.brainforge/README.md` (`:5-11`, `:22-35`, `:113`, `:128-138`),
`scaffold/.brainforge/canon-health.sh` (header `:22-23`), `scaffold/.claude/commands/sync.md:54`,
`scaffold/.claude/commands/add-source.md:24`, `scaffold/.claude/settings.json` (`$comment`),
`.claude-plugin/plugin.json`, `ROADMAP.md` (status section near `:303`)
Change: Every place that calls the drift or sync tripwire inline in `session-start.sh` names
`tripwires.sh` instead; the README gets a `## tripwires.sh` section (what it prints, that it never
pulls or writes, exits 0, why it exists: Studio). Add `".brainforge/tripwires.sh"` to
`runtime.bump` after `session-start.sh`; version `0.16.1` → `0.17.0`. ROADMAP gets a new
`## … (v0.17.0)` section after the v0.16 one, matching its one-section-per-release shape.
Verify: `grep -rn 'tripwire' scaffold/.brainforge/README.md scaffold/.brainforge/canon-health.sh scaffold/.claude | grep -v tripwires.sh`
→ no line still says a drift or sync tripwire lives inline in `session-start.sh` (read each hit);
`git show HEAD:.claude-plugin/plugin.json | grep -E '"version"|tripwires'` after commit → `0.17.0` and the bump entry.

#### Step A5 — Whole suite, cleanup pass, PR

Files: none new
Change: Run `/senior-engineering-cleanup-pass` scoped to the Part A diff. Then the full suite. Open a
PR (body via `write-like-jordan`). Jordan merges.
Verify: the baseline loop → `31 PASS`; CI `test.yml` green on the PR (`gh pr checks`).

### Part B — Studio v0 (branch `feat/studio-v0`, from main after Part A merges)

#### Step B1 — The package

Files: `studio/package.json`, `studio/tsconfig.json`, `studio/vite.config.ts`, `studio/index.html`,
`studio/src/main.tsx`, `studio/server/index.ts`, `studio/bin/brainforge-studio.js`, `studio/README.md`
Change: One npm package, `"name": "brainforge-studio"`, `"version": "0.0.0"`, **`"private": true`**
(B12 removes it, so nothing can be published by accident), `"engines": {"node": ">=20"}`,
`"bin": {"brainforge-studio": "bin/brainforge-studio.js"}`, `"license": "MIT"`. Vite + React +
TypeScript for `src/`, Hono on `@hono/node-server` for `server/`, Vitest, Playwright. Scripts:
`dev`, `build` (Vite build plus server compile into `dist/`), `typecheck` (`tsc --noEmit`), `test`
(Vitest), `smoke` (Playwright). Pin exact versions in `package-lock.json`. Root `.gitignore`
already ignores `node_modules/` and `dist/`.
Verify: `cd studio && npm ci && npm run typecheck && npm run build` → exit 0; `git status --short | grep node_modules` → empty.

#### Step B2 — The temp-brain harness

Files: `studio/test/make-brain.ts`
Change: `makeBrain(opts)` builds a brain in a temp dir the way `tests/canon-health.test.sh` does:
copies `scaffold/.brainforge/*.sh`, copies
`evals/fixtures/acme-brain/{context,.brainforge/brain-manifest.json}` and then rewrites every
`last-reviewed:` in the copied `context/canon/**` to today (the fixture's own dates go stale on
2027-01-26), writes a synthetic `sources.json` and `.sync-state.json` (options: synced, never-synced,
TODO source; shapes from `scaffold/sources.json` `$examples` and the `sources()`/`entry()` helpers in
`tests/gate-github.test.sh:36-38`; always at least one github entry with no `localClone` and one
figma entry, with no `FIGMA_TOKEN` in a `.env`), writes extra canon docs whose `last-reviewed` is
relative to today (stale, never-reviewed, stalled draft) when asked,
optionally omits `tripwires.sh` or `brain-manifest.json` (an older brain), then `git init` and
commits. Returns the path; cleanup on test end.
Verify: `npm test -- make-brain` → a test asserts each option produces its files and that
`bash .brainforge/canon-health.sh` in a stale brain exits 1 and in a fresh one exits 0.

#### Step B3 — CLI and the locked-down server

Files: `studio/bin/brainforge-studio.js`, `studio/server/index.ts`, `studio/server/brain.ts`, `studio/test/server.test.ts`
Change: `brainforge-studio [path]` resolves the path (default cwd); refuses with a one-line message
and exit 1 when it has neither `sources.json` nor `.brainforge/`. Starts the server on `127.0.0.1`
on a free port (or `--port <n>`), generates a 32-byte random token, prints
`http://127.0.0.1:<port>/?t=<token>` and opens it in the default browser unless `--no-open` is
passed or `BRAINFORGE_STUDIO_NO_OPEN=1` is set (tests and CI use it). Every `/api/*` request needs the token (header or cookie set
from the first page load); otherwise 401. The server never writes inside the brain (only reads and
runs the brain's scripts).
Verify: `npm test -- server` → not-a-brain refuses with exit 1; `/api/*` without token → 401, with
token → 200; the listen address is `127.0.0.1`; after a full test run in a temp brain,
`git status --porcelain` there is unchanged.

#### Step B4 — Readers and script runners

Files: `studio/server/readers/{manifest,sources,canon}.ts`, `studio/server/scripts.ts`, `studio/server/routes.ts`, `studio/test/readers.test.ts`
Change: Readers for `brain-manifest.json` (Brain browser tree), `sources.json` +
`.sync-state.json` (Sources list, times shown as-is), and canon file contents. `scripts.ts` runs
`.brainforge/canon-health.sh` (full report), `.brainforge/tripwires.sh <brain>`, and each
`gate-*.sh` with cwd = brain, a timeout, and no environment additions (gates read `.env`
themselves). Exit semantics per script: canon-health 1 = finding; gate 1 = error; tripwires
non-zero = error. A missing file → that panel's `{ available: false, hint: "run /upgrade" }`; the gates panel keys on
`sources.json` (without it every gate exits 1, which is "not available", not an error).
Gates run only on demand (`POST /api/gates/run`), never on load.
Verify: `npm test -- readers` → stale brain shows a canon finding, fresh brain none; never-synced
brain shows the sync tripwire line; brain without `tripwires.sh` returns `available: false` for that
panel and the rest still load; gate with no credentials returns its own `not-checked` line.

#### Step B5 — Setup check

Files: `studio/server/prereqs.ts`, `studio/test/prereqs.test.ts`
Change: Checks `node` (>= 20), `git`, `python3`, `gh` (installed and `gh auth status`), `claude`.
v0 blocks only on `node`, `git`, `python3`; `gh` and `claude` show as "needed for later phases"
without blocking. Each missing item has a one-line install hint.
Verify: `npm test -- prereqs` with `PATH` pointed at a stub dir → each missing tool reported, and
blocking vs not as above.

#### Step B6 — Draft tokens and the theme switch

Files: `studio/src/styles/tokens.css` (empty, header comment: generated, never hand-edited),
`studio/src/styles/tokens.draft.css`, `studio/src/styles/fonts.css`, `studio/src/theme.ts`
Change: Per the design-system spec. `tokens.draft.css` holds two-tier tokens: primitives from
`~/Dev/brainforge-brand/apps/site/app/globals.css:7-41` (void, canon, derived, seam, stale, bone,
slate, line; the three fonts; the two easings) and semantic tokens over them (`--color-bg-*`,
`--color-text-*`, `--color-border-*`, `--color-accent-*`, `--color-status-stale`), a ~6-step type
scale, spacing and radius. Dark on `:root`; a first light palette on `[data-theme="light"]`.
`theme.ts`: stored choice, else `prefers-color-scheme`, sets `data-theme` on `<html>`; toggle
stores per browser (wrapped in try/catch). Load order: `fonts.css`, `tokens.css`, `tokens.draft.css`.
`fonts.css` imports the three `@fontsource` packages (row "Fonts").
Verify: `npm run build` → exit 0 and `grep -c 'fonts.googleapis\|fonts.gstatic' -r studio/dist` → 0;
`node -e` script that parses `tokens.draft.css` and asserts every semantic token resolves to a
primitive in both `:root` and `[data-theme="light"]` → exit 0. The semantic-only grep runs in B9,
once components exist.

#### Step B7 — product-design: inspect and intake (STOP: Jordan)

Files: `studio/SCREENS.md`
Change: Run `/product-design` steps 1–2. Proposed intake for Jordan to confirm: flow = setup screen
→ Health → Brain browser → Sources list; surface = desktop web (with a narrow-window floor of
1024px); hard screen = **Health** (most states: fresh, stale, never-reviewed, tripwires firing,
gates not run / running / changed / not-checked / error, older brain). Stop until Jordan confirms.
Verify: Jordan's answer recorded in `studio/SCREENS.md`.

#### Step B8 — product-design: target, inventory, two comps (STOP: Jordan)

Files: `studio/SCREENS.md`, `studio/design/precedent/`, `studio/design/comps/`
Change: `/product-design` steps 3–5: canon targets and Mobbin precedent for Health, the state
inventory and manifest, then two state-complete directions for Health in real code against the
temp-brain fixtures (both modes). Jordan kills one; record what it lost on. Never delete the killed
comp: comps live under `studio/design/comps/` (outside `src/`, served only by `npm run dev` through a
dev-only Vite entry) and `"files"` in `package.json` excludes `design/`, so neither ships in the package.
Verify: both comps render every manifest state (screenshots at 1440 and 1024, light and dark); the
kill line is in `SCREENS.md`; `npm pack --dry-run` lists nothing under `design/`.

#### Step B9 — product-design: spec, build, verify

Files: `studio/SCREENS.md`, `studio/src/**`
Change: `/product-design` steps 6–8: write `SCREENS.md`, build the signature moment first, then
Health to completion, then setup, Brain browser and Sources. Light-palette values are tuned live in
`tokens.draft.css`. Then `/senior-engineering-cleanup-pass` on `studio/`.
Verify: `/product-design`'s `verify.md` loop (gates, then its critic); plus the `verify` skill's
browser loop: `npm run build && node bin/brainforge-studio.js <temp brain> --no-open`, every screen
at 1440 and 1024, both themes, "Check sources now" exercised, console clean. And
`grep -rnE 'var\(--color-(void|canon|derived|seam|stale|bone|slate|line)' studio/src | grep -v 'styles/tokens'`
→ empty (components use semantic names only).

#### Step B10 — Playwright smoke

Files: `studio/test/smoke.spec.ts`, `studio/playwright.config.ts`
Change: Builds a temp brain (B2), starts the built CLI against it with `--no-open`, opens the printed URL, asserts
Health and the Brain browser render with their headings and at least one finding, and the console
has no errors. A second case without the token asserts the API refuses.
Verify: `npm run smoke` → 2 passed.

#### Step B11 — CI lane

Files: `.github/workflows/studio.yml`
Change: One job with id `studio`. On `pull_request` and `push` to `main` with
`paths: ['studio/**', 'scaffold/.brainforge/**', 'scaffold/sources.json', 'evals/fixtures/acme-brain/**', '.github/workflows/studio.yml']`
(the tests read those): Node 20, `npm ci`, `typecheck`, `test`, `build`, `npx playwright install --with-deps chromium`, `smoke`,
and a step that prints `::warning::` when `studio/src/styles/tokens.draft.css` has any declarations
(`grep -q -- '--[a-z]' studio/src/styles/tokens.draft.css`; the file always has a header comment).
Pin action versions by tag. `test.yml` untouched.
Verify: push the branch and open the Part B PR as a draft here; `gh pr checks` → `studio` green
and the draft warning visible in the run log (`gh run view --log | grep warning`).

#### Step B12 — Part B PR ready for review

Files: none new
Change: Mark the draft PR ready (body via `write-like-jordan`). Jordan merges.
Verify: `gh pr checks` → `test` and `studio` green.

#### Step B13 — First public release (Jordan)

Files: `studio/package.json`
Change: On a branch `release/studio-v0.1.0`: set `"version": "0.1.0"` and remove `"private"`; PR,
Jordan merges. Then Jordan, logged in to npm, tags `studio-v0.1.0` on that merge commit and runs
`npm publish` from `studio/`.
Verify: `npm view brainforge-studio version` → `0.1.0`; in a scratch dir `npx brainforge-studio`
refuses (not a brain); in a temp brain `npx brainforge-studio --no-open` prints a URL that serves
Health.

#### Step B14 — Plugin release pointing at Studio

Files: `README.md`, `commands/forge.md`, `.claude-plugin/plugin.json`
Change: Only after B13 is live. Branch `docs/studio-pointer`: a "Brainforge Studio" section in
`README.md` after "Reading a brain"; one sentence at the end of `commands/forge.md` step 5 pointing at
`npx brainforge-studio`; plugin version patch bump. PR; Jordan merges.
Verify: `git show HEAD:.claude-plugin/plugin.json | grep version` on the branch → the bumped version;
`grep -n 'brainforge-studio' README.md commands/forge.md` → one hit in each.
