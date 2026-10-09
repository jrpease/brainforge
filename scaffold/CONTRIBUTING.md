# Suggesting changes

This repo is **read-only on purpose** — that's what lets the whole team trust it. But read-only
must never mean "stuck with wrong information." If you spot something outdated, missing, or
incorrect, here's how to get it fixed. **Read-only consumption, open suggestion.**

## Found something wrong in `canon/` (voice, positioning, naming, principles)?

This is human-authored truth, so a human needs to review the change.

- **Quickest:** open a **GitHub Issue** describing what's wrong and what it should say.
- **Better (if you can):** open a **Pull Request** (fork → edit → PR). The domain owner reviews
  and merges. Find the owner in the file's frontmatter (`owner:`).
- **No GitHub?** Message the repo maintainer directly with the file name and the correction.

## Found something wrong in `derived/` (tokens, components, SKUs, site map)?

Derived content is **auto-generated** — editing the file won't help, because the next sync
overwrites it. The fix is one of:

1. **The upstream source is wrong** → fix it in Figma / the repo / the site. The next sync
   will pull the correction through.
2. **The upstream is right but the sync is stale** → ask the maintainer to run `/sync` (or wait
   for the scheduled sync). Check the file's `last-synced` first.
3. **The sync extracted it wrong** → open an Issue tagged `pipeline`. The extraction playbook in
   `pipeline/adapters/` needs adjusting.

## Suggesting a brand-new canon doc

Open an Issue proposing it. Keep scope in mind — see the non-goals in [README.md](README.md).
Not everything belongs here; a tight source of truth stays trustworthy.

## For maintainers

- Canon PRs require a human review and a bumped `last-reviewed` date.
- Derived changes arrive as sync PRs — eyeball the diff before merging; never let an
  unreviewed sync land.
