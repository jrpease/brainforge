# Post-merge manifest regeneration in CI

Status: built
Reviewed: 2026-09-29 — needs revision (applied the same day: empty-fingerprint churn, PR fallback for protected branches, stacking on `fix/release-backlog`, Plan fixes)
Date: 2026-09-29

## Goal

Two brain PRs open at once always conflict on `.brainforge/brain-manifest.json`, because both
regenerate it. Whichever side a human keeps, the default branch ends up with a fingerprint that
matches neither tree, and every subscriber sees "map predates the current content" until someone
regenerates by hand. The owner, working inside the brain, never sees the warning at all.

After this ships, a push to a brain's default branch that leaves the map stale gets one follow-up
regeneration (a commit, or a PR where the branch is protected), and a push that leaves it current
does nothing.

## Non-goals

- Replacing regeneration in `/sync` and `/approve-canon`. They still regenerate in the PR. CI is
  the backstop for merges, conflict resolutions and hand edits.
- Running `/sync`, `/drift` or any other brain command in CI. This job only regenerates the map.
- The source-side sync trigger and autonomous scheduled sync (separate roadmap items).
- Bypassing branch protection. A protected branch gets a PR, never a forced write.
- Existing brains' `.github/` contents beyond the one shipped workflow file.

## Decisions

Every row was chosen by Claude on 2026-09-29 under the user's standing instruction for that
session ("take your recommendations automatically, only flag me if you don't have a clear
answer"). None was put to the user individually. The protected-branch row is the least certain
and is called out in the session report.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Commit straight to the default branch, or open a PR | Commit straight to it when the push is allowed | The roadmap item names a push job. A PR would leave the stale window open until merged and would itself conflict with the next brain PR. Golden rule 4 is about a sync proposing content for a human gate (`scaffold/pipeline/README.md`); the map is a deterministic derivation of content already on the branch, and the commit touches only `.brainforge/`, which the fingerprint excludes. Accepted risk: a generator defect in any field other than the fingerprint now reaches subscribers without a human look | A CI-opened PR as the default |
| The push is refused (branch protection) | Push the regenerated map to a fixed branch, `brainforge/manifest-regen`, and open or update one PR from it. Fail red only when that fails too, naming the "Allow GitHub Actions to create pull requests" setting | Required-PR protection is the common company setup and this workflow ships by default. Failing red on every merge would teach owners to ignore the run or delete the workflow. One standing PR, force-updated, never piles up | Failing red on every merge; bypass tokens |
| When the job regenerates | Only when the committed `contextFingerprint` differs from `git rev-parse HEAD:<contextRoot>`, or the map is missing or has no fingerprint | This is the reader's staleness test (`synapse/hooks/session-start.sh`), so the job fixes what subscribers see and nothing else. Regenerating on every push would rewrite `generatedAt` and commit every day content was pushed | Regenerating unconditionally |
| The regenerated fingerprint is still empty | Fail (exit 1) naming the context root | An empty fingerprint means `contextRoot` is not a tree in `HEAD` (nothing committed under it, or a misconfigured root). Committing would churn one commit per push forever while subscribers still see "pre-schema-3" | Committing an empty-fingerprint map |
| Self-check after regenerating | Fail if the new fingerprint differs from `HEAD:<contextRoot>` | In a clean checkout the working tree equals `HEAD`, so a mismatch means the generator and the reader disagree. That should be loud, not committed | Committing whatever the generator printed |
| Loop guard | Rely on GitHub not triggering `on: push` for pushes made with `GITHUB_TOKEN`; the `CURRENT` check is the second guard | Documented GitHub behavior. Side effect worth stating: the regeneration commit also skips every other `on: push` workflow the brain has. If an owner swaps in a PAT, the second run sees `CURRENT` and stops | A commit-message skip marker |
| `main` moved while the job ran | Exit green without pushing when the remote default branch no longer equals `github.sha` (inequality, not ancestry) | The run for the newer push owns it. Inequality also covers a force-push that replaced the branch | Rebase-and-retry |
| Concurrency | One `concurrency` group per ref, `cancel-in-progress: false` | GitHub keeps one running and one pending run per group; a newer push replaces the pending one. A cancelled pending run on the default branch is expected, not a defect | Parallel runs racing to push |
| Where the logic lives | A shipped script, `.brainforge/regen-if-stale.sh`, which the workflow calls | Testable offline in `tests/`, like the other `.brainforge/` scripts | Inline workflow `run:` logic |
| How the files reach brains | Both join `runtime.bump`; `/forge`'s collision list gains the workflow's exact path | Anything in `scaffold/` not in `bump` is emitted once, so existing brains would never get it. As bump files `/upgrade` adds them, and deleting the workflow earns a tombstone, never a re-add: that is the opt-out. `/forge` emits unconditionally, so without the collision entry it could overwrite a same-named workflow | A `once` path; opt-in via `/forge` |
| Which branch | The repository's default branch, read from the push event | Brains are not all on `main` | A hardcoded `main` |
| Version and base | brainforge `0.13.0`, built on `fix/release-backlog` (`0.12.2`) | A new behavior in bump paths; minor matches past feature releases. `fix/release-backlog` edits `plugin.json`, `ROADMAP.md` and `scaffold/.brainforge/README.md`, which this also edits | Folding it into `0.12.2`; branching from `main` |

## Open questions

- None open. Live proof ran on a throwaway GitHub repo (`docs/proofs/ci-manifest-regeneration.md`).
  The Actions cost is accepted and stated in the brain README. The `workflow` token scope is
  documented in the brain README and in `/upgrade` §6.

## What shipped

- `scaffold/.brainforge/regen-if-stale.sh`: the stale test, regeneration, and the two refusals
  (empty fingerprint, fingerprint still differing from `HEAD`).
- `scaffold/.github/workflows/brainforge-manifest.yml`: the push job, the commit, the moved-branch
  exit, and the standing-PR fallback.
- `.claude-plugin/plugin.json`: both files in `runtime.bump`; version `0.13.0`.
- `commands/forge.md`: the workflow's exact path on the collision list.
- `commands/upgrade.md` §6: the `workflow` token scope for HTTPS pushes.
- `scaffold/.brainforge/README.md`: a section on the job.
- `tests/regen-if-stale.test.sh`: cases (a) to (i) plus the workflow's shape checks.
- `docs/proofs/ci-manifest-regeneration.md` and its index line; `ROADMAP.md` moves the item out
  of Deferred.

## Where it diverged

- **Test case (i) added.** Step 1's mutation check found that removing the "fingerprint still
  differs from `HEAD`" refusal broke no test. Case (i), an untracked file under the context root,
  now covers it.
- **Proof scenario 3d added.** Merging the standing PR, then confirming the next run reports
  `CURRENT`, closes the protected-branch loop the plan's three scenarios left open.
- **`/upgrade` §6 gained a line.** The spec's third open question recommended it; it is in this
  build rather than left open.
- Otherwise the steps ran as written.

## Plan

### Step 1 — the script and its tests

Files: `scaffold/.brainforge/regen-if-stale.sh`, `tests/regen-if-stale.test.sh`
Change: The script runs from the brain root, bash + git + sed only. Exit 0 silently when
`.brainforge/gen-manifest.sh` is absent. Read `contextRoot` and `contextFingerprint` from
`.brainforge/brain-manifest.json` with the reader's `sed` expressions
(`synapse/hooks/session-start.sh`). `live=$(git rev-parse --verify -q HEAD:<root>)`, root
defaulting to `context`. When the manifest exists and the fingerprint is non-empty and equals
`live`, print `CURRENT` and exit 0. Otherwise run `bash .brainforge/gen-manifest.sh`, re-read the
fingerprint, and exit 1 with a message when it is empty (naming the root) or differs from `live`
(printing both). On success print `REGENERATED <old or none> -> <new>`.
Tests, on a git fixture brain built with the shipped `gen-manifest.sh`: (a) a fresh committed map
→ `CURRENT`, manifest bytes unchanged; (b) content committed after the map → `REGENERATED`, new
fingerprint equals `HEAD:context`; (c) the conflict: two branches each add content and regenerate,
then `git merge` with `git checkout --ours -- .brainforge/brain-manifest.json && git commit`, →
`REGENERATED`; (d) a map with no `contextFingerprint` line → regenerated; (e) no
`gen-manifest.sh` → silent exit 0; (f) `BRAIN_CONTEXT_DIR=docs` honoured; (g) a second run →
`CURRENT`; (h) a context root with nothing committed → exit 1, manifest not reported as fixed.
Verify: `bash tests/regen-if-stale.test.sh` → `PASS regen-if-stale`; mutation: replace the
`CURRENT` comparison with a false test → the test fails.

### Step 2 — the workflow

Files: `scaffold/.github/workflows/brainforge-manifest.yml`, `tests/regen-if-stale.test.sh`
Change: `on: push`. One job, `if: github.ref == format('refs/heads/{0}',
github.event.repository.default_branch)`. `permissions: contents: write, pull-requests: write`.
`concurrency: { group: brainforge-manifest-${{ github.ref }}, cancel-in-progress: false }`.
Steps: `actions/checkout@v4` (default depth 1 is enough for `rev-parse HEAD:<root>`); run
`bash .brainforge/regen-if-stale.sh`; when `git status --porcelain
.brainforge/brain-manifest.json` is non-empty, commit it as `github-actions[bot]
<41898282+github-actions[bot]@users.noreply.github.com>` with `chore(manifest): regenerate after
<short sha>` and `git push origin HEAD:<default branch>`. When the push fails:
`git fetch origin <default branch>`; if `origin/<default branch>` differs from `github.sha`,
print a notice and exit 0; otherwise `git push -f origin HEAD:refs/heads/brainforge/manifest-regen`
and `gh pr create` (or, if one is open from that branch, leave it: the force-push updated it)
with `GH_TOKEN: ${{ github.token }}`; if that fails, exit 1 with a message naming branch
protection and the "Allow GitHub Actions to create and approve pull requests" setting.
Add shape checks to the test: the file parses as YAML (`ruby -ryaml -e 'YAML.load_file(ARGV[0])'`,
the parser `routing-smoke.sh` already requires; skip with a notice when ruby is absent), and it
names the script, `contents: write`, and the default-branch guard.
Verify: `bash tests/regen-if-stale.test.sh` → PASS. The live behaviour is proved by the live proof.

### Step 3 — the seam and `/forge`

Files: `.claude-plugin/plugin.json`, `commands/forge.md`
Change: add `.brainforge/regen-if-stale.sh` and `.github/workflows/brainforge-manifest.yml` to
`runtime.bump`; bump `version` to `0.13.0`. In `commands/forge.md` guard 3, add the exact path
`.github/workflows/brainforge-manifest.yml` to the collision list (a brain's own `.github/` is
allowed).
Verify: `grep -c 'regen-if-stale.sh\|brainforge-manifest.yml' .claude-plugin/plugin.json` → 2 and
`grep '"version": "0.13.0"' .claude-plugin/plugin.json`; an `/upgrade` dry run of this checkout
(the python fence extracted per `commands/forge.md`) against a fixture brain born from the
`0.12.2` scaffold reports `ADD` for both paths; `bash tests/emit-modes.test.sh && bash
tests/fence-contract.test.sh` → PASS.

### Step 4 — brain README

Files: `scaffold/.brainforge/README.md`
Change: a section on the job: what triggers it, the one commit (or the standing PR on a protected
branch), the loop guard and that the commit skips other push workflows, deleting the workflow as
the opt-out, the Actions cost, and the `workflow` token scope for HTTPS pushes.
Verify: read by eye.

### Step 5 — live proof

A throwaway private GitHub repo scaffolded from this branch. Run (1)–(3) from the Open
questions, record run URLs and outcomes in `docs/proofs/ci-manifest-regeneration.md`.
Verify: each scenario's Actions run and resulting commit or PR, as recorded.

### Step 6 — ROADMAP

Files: `ROADMAP.md`
Change: after Step 5, remove the item from "Deferred" and add a bullet to the "Field hardening"
section `fix/release-backlog` adds, retitled to cover 0.13.0.
Verify: read by eye.
