# Contributing

Thanks for considering a contribution. This is the guide for contributing to **this repo** —
the builder. If you landed here from an emitted brain instead, see the next section.

## What this repo is

This repo is the **builder**: the generator, the sync-pipeline scaffold, and the Claude Code
commands that stand up and operate a "product-org brain" (`/walk`, `/sync`, `/add-adapter`,
`/publish`, `/upgrade`, …). Its output is a separate artifact — a **brain** — a self-sufficient
git repo scaffolded from `scaffold/` that a team owns and runs on its own.

Those two things have different contribution guides on purpose, because they have different
audiences:

- **This file** is for people extending the *builder* — most likely by adding a new sync
  adapter, or improving a command, template, or doc that ships to every brain.
- [`scaffold/CONTRIBUTING.md`](scaffold/CONTRIBUTING.md) is for people using an *emitted brain*
  — it explains how to suggest a fix to that brain's `canon/` or `derived/` content. It ships
  inside every brain Brainforge scaffolds; it is not about this repo.

If you're not sure which one you want: if you're editing a `.md` template, a Claude Code
command, or an adapter *pattern* — you're here. If you're correcting a fact inside a brain
someone already built — you want the other one.

## Adding an adapter

The adapter bar exists to keep every sync playbook honest, and it is deliberately high:

**A new adapter must be proven live against a real source before it's accepted.** Speculative
adapters — ones written against documentation alone, never run against live data — are not
accepted.

To add one:

1. Copy [`scaffold/pipeline/ADAPTER-TEMPLATE.md`](scaffold/pipeline/ADAPTER-TEMPLATE.md) to
   `adapters/<source-type>.md` and fill every `<…>`. This is a contract, not a suggestion — fill
   the skeleton rather than reverse-engineering style from the built-ins. `/add-adapter` walks
   this for you.
2. Run it against a real, live instance of the source and confirm, live:
   - the **cheap change-detection gate fires** and correctly reports "nothing changed" on an
     unchanged source;
   - **extraction is deterministic** — the same input produces the same output, and counts /
     enumerations come from the source's own authoritative count field, never eyeballed or
     narrated;
   - a **second, immediate re-run short-circuits** at the cheap gate with zero heavy calls.

   That's golden rule #1 (see [`scaffold/pipeline/README.md`](scaffold/pipeline/README.md)),
   proven live, not asserted.
3. Write up what you proved as a proof summary and commit it under `docs/proofs/` — see the
   existing summaries there for the pattern (what was run, what the live run showed, any
   auth/transport findings worth folding back into the template).
4. Open a PR that includes the adapter file and its proof summary together.

For a full worked example of this path end to end — including the moment a live run caught a
real bug — see the Shopify walkthrough:
[`docs/walkthroughs/shopify-add-adapter.md`](docs/walkthroughs/shopify-add-adapter.md).

## The two corollary rules

Two mechanical seams in this repo mean a change can be *correct* and still silently fail to
reach anyone. Both are enforced by convention, not by CI, so hold yourself to them:

1. **Touching a `runtime.bump` path** (see the `runtime.bump` globs in
   [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json)) **⇒ bump `plugin.json`'s
   `version`**, or the change is invisible to `/upgrade` — brains that already exist will never
   see it.
2. **Touching a published path** (a `publish.include` match, or a `publish.map` source — both
   defined in the same `plugin.json`) **⇒ re-run `/publish` before the next release**, or the
   public tree drifts from what's actually in this repo.

## PR expectations

- Keep branches **small and single-purpose** — one adapter, one command fix, one doc change.
  Easier to review, easier to revert.
- PRs are **human-merged, never auto-merged**. Expect a real review, and expect to be asked for
  the live proof if you're touching an adapter.
- If your change touches `scaffold/`, keep the `{{ORG}}` templating intact — those placeholders
  are filled in at scaffold time for each brain; a hardcoded value there breaks every brain that
  gets emitted after your change.

## License

Contributions are made under the same license as the rest of the repo: [MIT](LICENSE).
