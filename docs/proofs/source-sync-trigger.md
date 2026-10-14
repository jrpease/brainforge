# Source-side sync trigger: live proof

Proven 2026-10-14 on two throwaway private GitHub repos
([spec](../specs/2026-10-13-source-sync-trigger.md)). `bf-trigger-brain` was forged from the
0.16.0 scaffold with one `repos` entry, `web`, whose `localClone` points nowhere, so every check
below ran from CI and none from a laptop. `bf-trigger-source` carried `src/`, `notes/` and a
`.brainforge-source.yml` (block form) that excludes `notes/**` and `.github/**`. The brain's
`lastSha` was set to the source head after that file landed. The token was a fine-grained token
whose only repository was the brain, with **Contents: Read** and **Issues: Read and write**: the
exact permissions the adapter documents, so the proof covers least privilege as well as the
mechanics. Every run is a real GitHub Actions run on `ubuntu-latest`.

## What was run

| # | Scenario | Run result | `source-signal.sh` printed |
|---|---|---|---|
| 0 | The push that installs the workflow (`.github/**`, out of scope) | success | `nothing to do (caught up, no open issue)` |
| 1 | A change under `notes/` (out of scope) | success | `nothing to do (caught up, no open issue)` |
| 2 | A change to `src/app.ts` | success | `opened #1`; the body lists `src/app.ts`, both heads and a compare link |
| 3 | A new file, `src/util.ts` | success | `updated #1`; still one open issue, listing both paths |
| 4 | The brain's `lastSha` advanced to the source head (what a sync does), then `workflow_dispatch` | success | `closed #1`, comment ``Caught up at `5db659e…` `` |
| 5 | A change to `src/app.ts`, then a brain PR advancing `lastSha` whose body carries `Closes #2`, merged | success | `opened #2`; the merge closed #2 (`COMPLETED`). A dispatch afterwards: `nothing to do (caught up, no open issue)` |
| 6 | The entry's `remote` pointed at another repo, then `workflow_dispatch` | success | `opened #4`, "**web** cannot be checked: origin https://github.com/jrpease/bf-trigger-source does not match remote github.com/jrpease/bf-not-this-repo." |
| 7 | With #4 open, the token's Issues permission set to No access, then a push | **failure**, as designed | `source-signal (brain jrpease/bf-trigger-brain): gh api repos/{owner}/{repo}/issues?labels=brainforge-sync&state=open&per_page=100 failed: gh: Resource not accessible by personal access token (HTTP 403)` |

Run 5's PR body was written by following `/sync` step 4's new lookup by hand, not by a real
`/sync`. The issue numbers skip #3 because that number went to run 5's pull request.

`never` and `not-checked` were not run live. Both stop before any `gh` call, so the live system
adds nothing the offline test (`tests/source-signal.test.sh`) does not already cover.

## What the proof taught

- **An empty secret fails with a misleading error.** The first secret was set with
  `gh secret set` from a shell with no terminal. With nothing to prompt, it read an empty stdin
  and saved an empty value, without an error. The run then failed at the brain checkout with
  "Input required and not supplied: token", which reads like a missing secret rather than an
  empty one. The adapter's install step now says to pipe the token in, and names that error.
- **The workflow file is in scope by default.** Unless `.github/**` is excluded, the push that
  installs the trigger opens the first issue, for the workflow file itself. The proof excluded
  it; the adapter now says so.

Nothing in the scripts or the template changed as a result. The REST lookup found the open issue
on every run, including run 3, which started 18 seconds after run 2 created the issue, so no duplicate was ever opened.
