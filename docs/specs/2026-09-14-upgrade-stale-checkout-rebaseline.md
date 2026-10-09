# /upgrade: stale checkouts and reconciled baselines

Status: built
Date: 2026-09-14

## Goal

Two bugs in `/upgrade`, both found by running it for real against a brain going from 0.8.0 to
0.10.0.

1. **A stale checkout made the upgrade a silent no-op.** §1 routed on the brain's
   `runtime-version` against `V` from the local checkout. The only checkout on the operator's
   machine was the plugin marketplace clone, which nothing auto-pulls. It was six commits behind
   and still shipped 0.8.0, the brain's own version, so the command said "up to date (v0.8.0)" to
   a brain two minor versions behind. The guard caught a brain newer than the checkout, and
   nothing caught the two being equal because the checkout was behind.
2. **A reconciled file re-flagged against a baseline two versions old.** Three files reconciled at
   0.7.0 flagged again at 0.10.0. The flag itself was correct, since they carry permanent local
   additions, but it was measured against the 0.7.0 baseline, so the PR re-presented upstream
   changes already dealt with. Repeat that and people stop reading the flagged section.

After this ships, "up to date" is only printed from a checkout proven current, and a reconciled
file can have its baseline moved forward without losing the protection the flag gives it.

## Findings

**The installed plugin copy is not a git repo.** `~/.claude*/plugins/cache/<marketplace>/brainforge/<version>/`
has no `.git`, and it goes stale in the same way the marketplace clone does. A "fetch and count"
check alone would have refused every run from it, so it needs its own path: compare `V` against
the published `plugin.json`.

**`urllib` fails TLS on a python.org `python3` on macOS** (no CA bundle), while `curl` succeeds.
Found in a live run against the real cache copy. The version read goes through `curl` first.

**The classifier flags on bytes, not on upstream change.** `FLAG-MODIFIED` fires whenever the
on-disk file differs from its baseline. A re-baselined file with local additions still differs, so
it still flags on every later upgrade.

**Nothing in `upgrade.md` read the baseline except that equality check.** The "changes since
baseline" view the operator reconciled against was worked out by hand. A re-baseline step alone
would have been bookkeeping nothing consumed (caught in review). So the delta is now a documented
read-only step: find the newest commit whose emitted `scaffold/<file>` hashes to the baseline and
diff it against HEAD. That is the consumer that makes re-baselining matter.

**Two things a first cut got wrong, caught in review.** `git rev-parse --is-inside-work-tree`
is true for an enclosing repo, so a plugin cache copy under a dotfiles `$HOME` was judged as that
repo (refused as dirty for a changed `.zshrc`). And two failure paths (a failed `status`, a failed
`rev-list`) read as clean and current. Both fixed and tested.

## Non-goals

- **Automatic re-baselining.** The classifier cannot know a file was reconciled. Only the person
  who did it can.
- **Changing when `FLAG-MODIFIED` fires.** Suppressing it when upstream is unchanged since the
  baseline would be a classifier change with its own risks. See Open questions.
- **Guarding the adoption pass.** A brain with no manifest (including `/forge`'s bootstrap, which
  may run offline against a tree it just emitted) skips the check.

## Decisions

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Where the freshness check lives | Inside the §3 python fence, run before routing whenever a manifest exists | A prose guard can be skipped; the script is the contract. Keeps one python fence and the same CLI, so `/forge` is untouched | A bash guard in §0 only |
| Compare against | `origin/HEAD`, else `origin/main`, after `git fetch origin` with prompts disabled (`GIT_TERMINAL_PROMPT=0`, ssh batch mode), only when `BF` is itself the repo root | The report's fix. The default branch is what gets published; a feature branch's upstream would let an old branch pass | `@{upstream}` |
| Dirty checkout | **Refuse** (tracked changes only) | The manifest records `emitted-from` as HEAD; dirty bytes make that a lie. Untracked files are ignored so a scratch `bf-upgrade.py` does not trip it | Warn and continue |
| Detached checkout | **Allow**, judged against the default branch like any other | A detached HEAD at a current commit is legitimate; one at an old tag is caught by the count | Refusing all detached heads |
| Non-git copy | Read the published `plugin.json` at `repository`, refuse if newer | The installed plugin is the common path and is not git | Refusing every non-git copy |
| Cannot verify (fetch fails, offline, no `repository`) | **Refuse**, `UNVERIFIED-CHECKOUT` | A check that cannot run must not read as a pass | Falling back to local `V` |
| Upstream delta | A documented read-only bash step in §3; its first line goes on the flagged file's PR body line | Gives the baseline a consumer. After a re-baseline it prints `NO-UPSTREAM-CHANGE` until upstream edits the file again | Leaving the diff to the operator's judgment |
| Re-baseline | A documented bash step in §3, refused unless the file still differs from shipped, the manifest is at `V`, and a baseline exists | The report's fix 2 and its stated safety condition. A baseline equal to on-disk bytes turns the next run into an unflagged overwrite | A classifier change |
| Version | brainforge 0.12.0 → 0.12.1 | `commands/**` is published behavior | |

## What shipped

- `commands/upgrade.md` §1: the freshness table, its limits (compares `origin`; the non-git path
  compares versions only), and why. §3: `checkout_current()` in the script, the "Upstream delta
  for a flagged file" and "Re-baseline a reconciled file" steps, and the rewrite-rules note. §6:
  the delta and reconciled lines in the PR body.
- `tests/upgrade-stale-checkout.test.sh`: level, the reported bug (origin one commit ahead at a new
  version; fails on the old `upgrade.md` with "stale checkout must exit 1"), pull-then-route,
  dirty, untracked scratch file, detached, unreachable origin, non-git stale and current, a copy
  inside another (dirty) repo, a checkout with no `origin`, non-git with no `repository`.
- `tests/upgrade-rebaseline.test.sh`: runs both of the doc's bash blocks as shipped, with a
  `{{ORG}}` placeholder in the fixture so the emitted hash is really tested. Delta: shows the
  upstream edit; after a re-baseline, `NO-UPSTREAM-CHANGE`; without one, the already-reconciled
  change is re-presented (the reported bug); a later edit shows only itself. Re-baseline: flag, refusal
  when identical to shipped (manifest untouched), refusal with no baseline, re-baseline to the
  shipped hash and never to on-disk bytes, idempotence, local additions surviving the next
  `--apply` with the new baseline carried forward, and refusal before `--apply`.
- `tests/upgrade-remove.test.sh`, `tests/upgrade-unbumped.test.sh`: fixture checkouts are now git
  repos level with an origin, so the guard can prove them current. No assertion changed.
- Live runs: the real 0.11.0 plugin cache copy reports `UP-TO-DATE` against the published 0.11.0.
  The real 0.8.0 copy reports `STALE-CHECKOUT published 0.11.0, this copy ships 0.8.0`. The real
  marketplace clone, level with origin, reports `UP-TO-DATE`.

## Open questions

- ~~**A file restored to stock stays flagged forever.**~~ Resolved 2026-09-29, see Amendment.

- **Should `FLAG-MODIFIED` stay quiet when shipped is unchanged since the baseline?** After a
  re-baseline, a file whose upstream never moves again still flags on every upgrade, now with
  `NO-UPSTREAM-CHANGE` beside it. Cheaper to read, but not gone.
- **A fork whose `origin` is the fork** passes the freshness check while behind the canonical repo.
  Documented in §1, not detected.

## Amendment 2026-09-29: stock files and reconciled collisions

The first open question happened for real. A production brain's 0.10.0 → 0.13.1 upgrade reconciled
`gen-manifest.sh` and `.brainforge/README.md` by taking shipped, and the step refused both. Left
alone, each would flag on every upgrade. The same upgrade reconciled a collision
(`pipeline/README.md`: shipped plus one local line), which had no path into the manifest at all,
so it would re-flag as a whole-file collision every time.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| File identical to shipped | Write the shipped hash, print `ADOPTED-STOCK` | The file *is* shipped, so the next overwrite loses nothing. Review had already called it safe | Keeping the refusal |
| Reconciled collision (no baseline, differs from shipped) | Write the shipped hash, print `ADOPTED-COLLISION` | It then flags as `FLAG-MODIFIED` with a delta from `V`, not a whole-file collision. The baseline still never equals the file's bytes, so it can't read as safe to overwrite | Collisions staying out of the manifest forever |
| Version | brainforge 0.13.1 → 0.13.2 | `commands/**` is published behavior | |

The invariant narrows rather than goes: a file that *differs* from shipped never gets a baseline
equal to its own bytes. Tested in `tests/upgrade-rebaseline.test.sh`: a stock file is adopted and the
next run is `UP-TO-DATE`; an adopted collision flags as `FLAG-MODIFIED` at the next version with
`NO-UPSTREAM-CHANGE` and its local lines intact; an unshipped file is refused.
