# Contributing

Thanks for considering a contribution. This is the guide for contributing to **this repo**, the
builder. If you landed here from an emitted brain instead, see the next section.

## What this repo is

This repo is the **builder**: the generator, the sync-pipeline scaffold, and the Claude Code
commands that stand up and operate a "product-org brain" (`/forge`, `/sync`, `/add-adapter`,
`/publish`, `/upgrade`, …). What it produces is a separate thing called a **brain**: a
self-sufficient git repo built from `scaffold/` (the set of starting files a brain is created
from) that a team owns and runs on its own.

Those two things have different contribution guides on purpose, because they have different
audiences:

- **This file** is for people extending the *builder*, most likely by adding a new sync
  adapter (the small playbook that pulls from one tool), or improving a command, template, or
  doc that ships to every brain.
- [`scaffold/CONTRIBUTING.md`](scaffold/CONTRIBUTING.md) is for people using an *emitted brain*:
  it explains how to suggest a fix to that brain's `canon/` (the human-authored content) or
  `derived/` (the auto-synced content) files. It ships inside every brain Brainforge creates; it
  is not about this repo.

If you're not sure which one you want: if you're editing a `.md` template, a Claude Code
command, or an adapter *pattern*, you're here. If you're correcting a fact inside a brain
someone already built, you want the other one.

## Adding an adapter

The adapter bar exists to keep every sync playbook honest, and it is deliberately high:

**A new adapter must be proven live against a real source before it's accepted.** Speculative
adapters, ones written against documentation alone and never run against live data, are not
accepted.

To add one:

1. Copy [`scaffold/pipeline/ADAPTER-TEMPLATE.md`](scaffold/pipeline/ADAPTER-TEMPLATE.md) to
   `adapters/<source-type>.md` and fill every `<…>`. This is a contract, not a suggestion: fill
   the skeleton rather than reverse-engineering style from the built-ins. `/add-adapter` walks
   this for you.
2. Run it against a real, live instance of the source and confirm, live:
   - the **cheap change-detection gate fires** and correctly reports "nothing changed" on an
     unchanged source;
   - **extraction is deterministic** (the same input produces the same output every time), and
     counts and enumerations come from the source's own authoritative count field, never
     eyeballed or narrated;
   - a **second, immediate re-run short-circuits** at the cheap gate with zero heavy calls.

   That's golden rule #1 (see [`scaffold/pipeline/README.md`](scaffold/pipeline/README.md)),
   proven live, not asserted.
3. Write up what you proved as a proof summary and commit it under `docs/proofs/`. See the
   existing summaries there for the pattern (what was run, what the live run showed, any
   auth/transport findings worth folding back into the template).
4. Open a PR that includes the adapter file and its proof summary together.

For a full worked example of this path end to end, including the moment a live run caught a
real bug, see the Shopify walkthrough:
[`docs/walkthroughs/shopify-add-adapter.md`](docs/walkthroughs/shopify-add-adapter.md).

## The three corollary rules

Three mechanical seams in this repo mean a change can be *correct* and still silently fail to
reach anyone. All three are enforced by convention, not by CI, so hold yourself to them:

1. **Touching a `runtime.bump` path** (see the `runtime.bump` globs in
   [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json)) **means you bump `plugin.json`'s
   `version`**, or the change is invisible to `/upgrade`: brains that already exist will never
   see it.
2. **Touching a published path** (a `publish.include` match, or a `publish.map` source, both
   defined in the same `plugin.json`) **means you re-run `/publish` before the next release**, or
   the public tree drifts from what's actually in this repo.
3. **Touching published *behavior* means you bump `plugin.json`'s `version`.** Republishing at
   the same version is **invisible to `claude plugin update`**: installed users keep the old
   behavior until they force a reinstall (proven the hard way during Phase 4: a republished
   `plugin.json` at the same `0.3.0` needed a forced reinstall to take). Published behavior is
   anything a plugin install *executes, dispatches on, or emits*: `commands/**`,
   `.claude-plugin/**`, `scaffold/**`, `synapse/**`. Docs-only published paths (`README.md`,
   `DESIGN.md`, `ROADMAP.md`, this file, `docs/**`) and `evals/**` need rule 2 but **not** a
   bump. Neither does a comment-only edit *inside* a behavior file, such as a `$comment` in
   `plugin.json` or a `#` line in a script, since nothing an install executes actually changed.
   **When the line between comment and behavior is at all unclear, bump.** A spurious version
   bump costs nothing; a behavior change that never reaches installed users is the failure this
   rule exists to prevent.

   Rule 3 is not implied by rule 1. `runtime.bump` covers what `/upgrade` re-emits into
   *existing* brains; rule 3 covers what a *plugin install* carries. The gap between them is
   real: `scaffold/` **`once`** paths (`CLAUDE.md`, `sources.json`, `templates/**`, meant to be
   emitted once at birth and then owned by the brain) sit outside `runtime.bump` by design, so
   changing one is correctly invisible to `/upgrade`, but without a version bump it also never
   reaches the next brain anyone forges.

## PR expectations

- Keep branches **small and single-purpose**: one adapter, one command fix, one doc change.
  Easier to review, easier to revert.
- PRs are **human-merged, never auto-merged**. Expect a real review, and expect to be asked for
  the live proof if you're touching an adapter.
- If your change touches `scaffold/`, keep the `{{ORG}}` templating intact. Those placeholders
  are filled in for each brain when it's created; a hardcoded value there breaks every brain
  built after your change.

## License

Contributions are made under the same license as the rest of the repo: [MIT](LICENSE).
