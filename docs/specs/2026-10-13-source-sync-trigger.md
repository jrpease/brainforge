# Source-side sync trigger

Status: planned
Reviewed: 2026-10-13 — ready to build (second pass; its two setup fixes and two clarifications applied)
Date: 2026-10-13

## Goal

Today a GitHub source's freshness depends on someone running `/sync` or `/sync-health` in the
brain, on a machine with a clone at `localClone`. If nobody does, the brain goes quietly stale.
That is the failure that teaches a team to stop trusting it. The 2026-09-08 audit found the
audited team had already built its own answer, a GitHub Action in the source repo that opens a
sync issue on the brain when in-scope paths change. The audit spec
([2026-09-09-audit-hardening.md](2026-09-09-audit-hardening.md)) and the roadmap took the idea.

After this ships, a source repo can install one workflow. On every push to the tracked branch it
runs the brain's own GitHub gate and keeps **one standing issue** in the brain per source:

- opened or updated when in-scope files changed since the last sync;
- closed when the source is caught up;
- closed by the sync PR that brings the source current.

The signal is the gate's own verdict, so it says exactly what `/sync-health` would say, from
nobody's laptop.

## Non-goals

- **Running the sync.** A sync needs Claude (extraction and summarising are model work). The
  trigger only makes a needed sync visible. Autonomous sync stays deferred.
- **Other adapters.** Figma, Monday and GA have no repo to put an Action in; GA changes daily
  anyway. A website deploy hook is conceivable and is not this spec.
- **A GitHub App.** A fine-grained token covers the need (see Decisions); an App is a later option.
- **Changing what "changed" means.** The gate decides; this spec adds no second scope rule.

## Decisions

Jordan delegated these on 2026-10-13 ("take your recommendations"). Each row is Claude's call.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| What the trigger does | Signals; never syncs | `/sync` is Claude Code work; CI has no model and no API key, by design | A headless-Claude sync in CI |
| Signal form | One standing issue per source id in the brain repo, label `brainforge-sync`, title `Sync needed: <id>` | An issue is visible to every brain watcher and needs only Issues permission. One issue per source, edited in place, cannot pile up | `repository_dispatch` (needs Contents: write on the brain, and the brain-side job could not sync anyway); one issue per push |
| Who decides "changed" | The brain's real `gate-github.sh`, run in the source repo's Action against a checkout of the brain | Same code, same `.brainforge-source.yml` scope, same `lastSha`: the issue can never disagree with `/sync-health`. False alarms are the always-on-warning class fixed twice already | A `paths:` filter copied into the source workflow (drifts from the brain's scope the day either changes) |
| The clone in CI | `gate-github.sh --clone <path> <id>`: exactly one id; that path replaces `localClone` for the run. The remote check and the fetch run as usual | The CI checkout is not at the brain's `localClone`. One id keeps the override unambiguous | Rewriting `sources.json` in CI |
| Lifecycle | `changed`: open the issue, or edit the open one, with the delta list, head SHA and a compare link. `unchanged`: close the open issue with a "caught up at `<sha>`" comment, or nothing if none is open. `blocked`: open or edit, carrying the reason (a person must act). `never`: do nothing (the first sync is a human's job). `not-checked`: fail the run red. The issue lookup runs only for `changed`, `unchanged` and `blocked` | Every gate status has one stated outcome; a run that could not check never passes quietly. Cost, accepted: a brain-side problem (an expired token, a renamed brain) shows as a red check in the source team's CI, not the brain owner's; the failure names the brain so it is routable | Silently passing a run that could not fetch |
| Closing on sync | When `/sync` syncs a repo source and an open `brainforge-sync` issue exists for that id, the sync PR body carries `Closes #<n>` | The issue closes when the fix lands, not on the next push; if `gh` is missing or fails, the PR says so in one line and the next push closes it | — |
| Auth | A fine-grained personal access token, scoped to the brain repo only, with **Contents: read** and **Issues: read and write**, stored in the source repo as the secret `BRAINFORGE_BRAIN_TOKEN`. The install steps say: an org-owned brain needs the org to allow fine-grained tokens; the token expires and belongs to a person, and on expiry the source's run goes red until it is re-minted | Least privilege that works: reading the brain's state and editing its issues (Issues: write also covers creating the label). Contents: read on a brain is no more than any subscriber already has. Trade-off, accepted: freshness stops depending on one laptop and starts depending on one person's token, which fails loudly rather than quietly | A classic PAT (org-wide reach); the source repo's default `GITHUB_TOKEN` (cannot reach another repo); a GitHub App (deferred) |
| Where the logic lives | A brain script, `.brainforge/source-signal.sh <id> --clone <path>` (flag in any position): runs the gate (located beside itself, `$(dirname "$0")/gate-github.sh`), then opens, edits or closes the issue with `gh`. The workflow only checks out both repos and calls it | Logic in the brain is versioned, a bump path, testable offline with a `gh` stub, and the script reaches every brain through `/upgrade`. The workflow stays a thin template | Issue logic inline in workflow YAML |
| Finding the open issue | The REST issues list, `gh api "repos/{owner}/{repo}/issues?labels=brainforge-sync&state=open&per_page=100"`, dropping pull requests, then an exact title match locally | GitHub's search index lags a fresh create by seconds to minutes, so back-to-back pushes could open a duplicate. `gh issue list --label` is search-backed too (verified with `GH_DEBUG=api`: an `IssueSearch` query); the REST list reflects a create at once | `gh issue list`, with or without `--search` |
| Workflow template | `scaffold/templates/source-sync-trigger.yml`, copied into the source repo. Triggers: `push` to the tracked branch, and `workflow_dispatch`. Concurrency per source with `cancel-in-progress: true` (the newest push is the only one worth reporting). Source checked out with full history. Its `BRANCH` must match the entry's `branch`: the gate always diffs `origin/<entry.branch>`, so a mismatch only changes when it runs, never what it says | `lastSha` must be in history for the gate's ancestry check. A template a person copies is the honest install path: the brain cannot write to the source repo | Emitting it into the brain's own `.github/` |
| Older brains and the template | `scaffold/templates/**` is a `runtime.once` path, so `/upgrade` never brings the template into a brain forged earlier. The adapter's install steps link the template's public copy in this repo (`https://github.com/jrpease/brainforge/blob/main/scaffold/templates/source-sync-trigger.yml`) as the place to copy it from, for every brain | The file is copied into a different repo anyway; the brain's own copy is a convenience, not the source of truth. The link is `main`: if `source-signal.sh`'s interface (one id and `--clone`) ever changes, the link needs a version pin | Moving templates to a bump path for one file |
| Install path | The GitHub adapter gets a "Source-side trigger (optional)" section with the three install steps. `/add-source` mentions it in one line after adding a `repos` entry | Optional and additive: a brain without it works exactly as today | Making the trigger required |
| Versions | brainforge minor bump (new script and bump path, adapter and `/sync` prose). `source-signal.sh` joins `runtime.bump` | New behaviour | — |
| Proof bar | CONTRIBUTING's live-proof bar applies: two throwaway private repos (a source and a brain), a real token, and every lifecycle row exercised live, in `docs/proofs/source-sync-trigger.md` | The audit spec held this feature to that bar explicitly | Shipping on offline tests alone |

## Open questions

- **Auth shape, worth a yes.** The Auth row trades "freshness depends on one laptop" for "the
  signal depends on one person's token", and it is what lands in another team's repo. Claude's
  call under the delegation; Jordan may want to confirm it before a real team installs it.
  Not blocking the build.
- **The token for the live proof.** A fine-grained token can only be created in GitHub's web UI,
  by Jordan. Recommendation: Jordan creates one scoped to the throwaway brain repo, with exactly
  the permissions in the Auth row, so the proof proves least privilege, not just the mechanics.
  The broad `gh` token would prove the mechanics but not the permission claim the docs make.
  Needs Jordan at Step 6, as does merging run 5's PR.

## Plan

### Step 1 — `gate-github.sh --clone`

Files: `scaffold/.brainforge/gate-github.sh`, `tests/gate-github.test.sh`
Change: parse `--clone <path>` anywhere in the arguments. With it, exactly one id is required,
or exit 1 with a message on stderr and no stdout (misuse, like an unknown id). For that entry the
path replaces `localClone` (no `~` expansion needed, but harmless). Everything after is
unchanged: the remote check, the fetch, scope, ancestry, delta. Update the header's USAGE.
Verify: `bash tests/gate-github.test.sh` → `PASS`, with new cases:
- `--clone` pointing at a second clone of the same bare origin, while the entry's `localClone`
  points nowhere, reports the same status as the normal path;
- `--clone` with zero ids, two ids or an unknown id exits 1 with empty stdout;
- `--clone` at a clone whose origin is a different repo reports `blocked`.
Mutation: ignore `--clone` (use `localClone`) → the first case fails.

### Step 2 — `source-signal.sh`

Files: `scaffold/.brainforge/source-signal.sh` (new), `tests/source-signal.test.sh` (new),
`tests/lib/gh-stub.sh` (new)
Change: `bash .brainforge/source-signal.sh <id> --clone <path>` (`--clone` in any position), run
from the brain root.
- Runs `"$(dirname "$0")/gate-github.sh" --clone <path> <id>` and reads its one JSON line. No
  JSON → exit 1.
- For `changed`, `unchanged` and `blocked` only, finds the open issue with the REST list in the
  "Finding the open issue" row and an exact local match on `Sync needed: <id>`. `never` and `not-checked` call no `gh` at all.
- Acts on `status` per the Lifecycle row. The body is generated, never appended: the gate's
  `delta` as a list (first 50, then "and N more"), `fingerprint.lastSha`, the stored `lastSha`,
  and the compare link built from the entry's `remote` when it names github.com in any of the
  forms the gate accepts (`https://github.com/o/r`, `github.com/o/r`, `git@github.com:o/r.git`;
  the script normalises them itself, since the gate's `norm_remote` is not importable). It ends with
  "Run `/sync` in the brain to bring this source current.", then a one-line footer naming the
  script.
- Ensures the label exists (`gh label create brainforge-sync --force` before the first create).
- Prints one line saying what it did (`opened #n`, `updated #n`, `closed #n`, `nothing to do`).
- Exit 0 on every handled status; exit 1 on `not-checked`, on a `gh` failure, or on misuse.
The `gh` stub (`tests/lib/gh-stub.sh`) appends each call's arguments to `$GH_STUB_DIR/calls.log`;
answers the REST issues list with the contents of `$GH_STUB_DIR/issues.json` (default `[]`); prints
`https://github.com/o/b/issues/7` for `issue create`; prints nothing for `issue edit`,
`issue close` and `label create`; and exits 1 for any call when `$GH_STUB_DIR/fail` exists.
Verify: `bash tests/source-signal.test.sh` → `PASS`, against a local bare origin like
`gate-github.test.sh`, with one case per lifecycle row, plus: an open issue whose title only
contains `Sync needed: <id>` as a prefix of another id (`web` vs `web-docs`) is not edited; two
runs on `changed` edit, never open a second issue (the test writes the first run's issue into
`issues.json` before the second run). Mutations: open on every `changed` (no lookup);
close on `blocked`; exit 0 on `not-checked`; look up the issue on `never`. Each fails the test.
The same test parses the workflow template with `ruby -ryaml` (the `regen-if-stale.test.sh`
pattern), so CI checks it too; that case passes only once Step 3 exists, so build 2 and 3 together.

### Step 3 — The workflow template

Files: `scaffold/templates/source-sync-trigger.yml` (new)
Change: a commented workflow with `BRAIN_REPO` (`owner/name`), `SOURCE_ID` and `BRANCH` as the
three values to fill in. They are literal text, not `env:` entries: `on.push.branches` takes no
expressions and workflow-level `concurrency` cannot read `env`. `BRANCH` appears under `on:`;
`SOURCE_ID` in the concurrency group and the run step; `BRAIN_REPO` in the brain checkout and
`GH_REPO`. A comment at the top lists every occurrence. `on: push` (branches: the tracked branch) and `workflow_dispatch`.
`permissions: contents: read`. Concurrency group `brainforge-sync-<SOURCE_ID>`,
`cancel-in-progress: true`. Steps: check out the source with `fetch-depth: 0`; check out the brain
into `brain/` with `token: ${{ secrets.BRAINFORGE_BRAIN_TOKEN }}`; run
`bash .brainforge/source-signal.sh "$SOURCE_ID" --clone "$GITHUB_WORKSPACE"` from `brain/`, with
`GH_TOKEN` set to the same secret and `GH_REPO` to `BRAIN_REPO`. A comment at the top names the
token's exact permissions.
Verify: `bash tests/source-signal.test.sh` (its template-parse case) → `PASS`; the live run in
Step 6 is the real check.

### Step 4 — Prose: adapter, `/sync`, `/add-source`, contract

Files: `scaffold/pipeline/adapters/github.md`, `scaffold/.claude/commands/sync.md`,
`scaffold/.claude/commands/add-source.md`, `scaffold/.brainforge/README.md`,
`.claude-plugin/plugin.json` (`runtime.bump`)
Change: the adapter gains "Source-side trigger (optional)": what it does, the three install
steps (create the token with the stated permissions, add the secret, copy the template from its
public URL and fill in three values, `BRANCH` matching the entry), the org-setting and expiry
notes from the Auth row, and what each issue state means. `/sync` step 4 ("Open a PR"): for each
repo source synced, if an open `brainforge-sync` issue titled
`Sync needed: <id>` exists, add `Closes #<n>`; if `gh` is unavailable, one line saying the issue
was not linked. `/add-source`: one line after a `repos` entry is added, pointing at the adapter
section. `.brainforge/README.md`: `source-signal.sh` and `gate-github.sh --clone` in its script
list. Add `.brainforge/source-signal.sh` to `runtime.bump`.
Verify: by eye; `grep -n "source-signal" .claude-plugin/plugin.json` prints the bump entry.

### Step 5 — Versions and the full suite

Files: `.claude-plugin/plugin.json`
Change: bump the minor version.
Verify: every `tests/*.test.sh` prints `PASS` (count from running it, not from prose);
`git show HEAD:.claude-plugin/plugin.json` shows the bump once committed.

### Step 6 — Live proof

Files: `docs/proofs/source-sync-trigger.md` (new), `docs/proofs/README.md`, `ROADMAP.md`
Change: two throwaway private repos under Jordan's account, `bf-trigger-source` and
`bf-trigger-brain`. The brain is forged from this checkout with one `repos` entry for the source
and a `.sync-state.json`. The source first commits a `.brainforge-source.yml` in the block form
the adapter documents (`version: 1`, then `never-summarize:` with one item `- "notes/**"`; the
gate's strict parser rejects the flow form `["notes/**"]`), so `notes/` is out of scope. Only
then is the source head recorded as the brain's `lastSha`: the yml is itself an in-scope path. Jordan creates the fine-grained
token (Open questions). Then, live:
1. push a change under `notes/` → the run is green, no issue;
2. push an in-scope change → `opened #n` with the right file;
3. push another in-scope change → `updated #n`, still one open issue;
4. advance the brain's `lastSha` to the source head (what a sync does) and trigger the workflow
   with `workflow_dispatch` → `closed #n` with the caught-up comment;
5. push an in-scope change (a fresh `opened #m`), then follow `/sync` step 4's new lookup by hand
   in the brain to produce the PR body line, open a PR that advances `lastSha` with that body,
   and Jordan merges it → `#m` closes. The proof says the lookup was followed by hand, not run
   by a real `/sync`;
6. point the entry's `remote` at another repo → `blocked`, issue carries the reason;
7. with run 6's issue still open, remove the token's Issues permission and push → the run goes
   red, nothing silent.
Record each run's outcome and the script's one-line output in a table (no run links: the repos
are deleted, as in `docs/proofs/ci-manifest-regeneration.md`). Delete both repos and the token
after.
Roadmap: move the item from Deferred to done.
Verify: every lifecycle row has a recorded run with its one-line output.
