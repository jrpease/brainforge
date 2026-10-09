# CI manifest regeneration: live proof

Proven 2026-09-29 on a throwaway private GitHub repo, scaffolded from the 0.13.0 scaffold with
one synthetic canon domain. Every run below is a real GitHub Actions run on `ubuntu-latest`.

## What was run

| # | Scenario | Push | Run result | Outcome |
|---|---|---|---|---|
| 0 | Birth: the map was generated before the first commit | brain birth | success, `CURRENT` | Nothing landed. The fingerprint computed on macOS matched the runner's `git rev-parse HEAD:context` on Linux |
| 1 | A canon edit pushed without regenerating the map | one commit to `main` | success, `REGENERATED` | The bot committed `chore(manifest): regenerate after <sha>`; the new fingerprint equals `HEAD:context` |
| 2 | Two branches each regenerate; the merge conflicts on the manifest and keeps one side | merge commit to `main` | success, `REGENERATED` | Before: map `d41e01f`, content `02835a0`, matching neither branch. After the bot's commit: both `02835a0` |
| 3a | `main` protected (PRs required); Actions not allowed to open PRs | admin push of a canon edit | **failure** (attempt 1), as designed | GitHub refused the bot's push (`GH006`). The run failed red, naming the "Allow GitHub Actions to create and approve pull requests" setting |
| 3b | Same, with that setting on (attempt 2 of the 3a run) | none | success | One PR opened from `brainforge/manifest-regen`, touching only `.brainforge/brain-manifest.json` |
| 3c | Another canon edit while that PR is open | admin push | success | The PR was updated in place, not duplicated; its map matched `main`'s new content |
| 3d | The PR merged | merge commit | success, `CURRENT` | `main`'s map and content agree; nothing landed |

After code review tightened the fallback path (the moved-branch check now fails red when the
remote ref cannot be resolved, and an existing standing PR counts as success after a transient
API failure), the updated workflow was pushed and re-run: a workflow-only push read `CURRENT`, and
a canon edit on the protected branch opened a new standing PR touching only the map.

**No loop.** The bot's commits in scenarios 1 and 2 triggered no runs: runs appeared only for
the pushes made by a person, as GitHub documents for `GITHUB_TOKEN` pushes.

## What the proof taught

Nothing in the shipped files changed as a result of the live runs. Two things were confirmed
rather than assumed:

- **The fingerprint is portable.** A map generated on macOS is `CURRENT` on a Linux runner, so a
  brain maintained on laptops and checked in CI agrees about staleness.
- **The workflow's default permissions are enough.** The repo's default `GITHUB_TOKEN` was
  read-only; the workflow's own `permissions:` block was sufficient to commit and to open the PR.
