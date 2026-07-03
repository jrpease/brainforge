# Walkthrough: adding Shopify via `/add-adapter`

This is an anonymized narrative of a real production run: an org's live Shopify store, added to
their live brain, through the documented extension path — not a demo, not a dry run. It's the
worked proof that `/add-adapter` is real, and it doubles as the recipe for adding any source
Brainforge doesn't ship a built-in for.

## 1. Why `/add-adapter` exists

Brainforge ships built-in adapters for the sources most product orgs already have (GitHub, Figma,
Monday, GA, a generic website). No adapter roster covers every source a real org runs on — Stripe,
Linear, an internal API, whatever's next. Rather than treat "not built in" as a wall, the extension
path treats [`scaffold/pipeline/ADAPTER-TEMPLATE.md`](../../scaffold/pipeline/ADAPTER-TEMPLATE.md)
as the actual **API surface**: a fixed skeleton — cheap gate, extract, emit shape, provenance,
command — that any new source fills in prose. `/add-adapter` walks a maintainer through filling it.
The bar for landing one is that it has to run against a real, live instance of the source, not just
read plausibly — see [`CONTRIBUTING.md`](../../CONTRIBUTING.md#adding-an-adapter).

Shopify is the adapter that proved this end to end, because it happened to already exist in an
older shape and needed re-adding through the new path — which turned out to be a harder, more
honest test than adding a brand-new source from scratch.

## 2. Starting point

The org had a live brain — a working "product-org brain" repo, synced against real sources for
months — but it was running an **older runtime**. It had `/sync`, `/add-source`, `/sync-health`,
`/drift`, and a flat `pipeline/sync-<type>.md` per source, but no `pipeline/adapters/` directory,
no `ADAPTER-TEMPLATE.md`, and no `/add-adapter`, `/walk`, `/draft-canon`, or `/approve-canon`.

Shopify was already present, but through the old path: a flat `pipeline/sync-shopify.md`, a
`sources.json` entry for the store, and `context/derived/shopify/` files that had been produced by
a one-time bootstrap and never run through a real steady-state sync. The store itself was real and
live, with an admin API credential on file.

The goal wasn't a rewrite of the whole brain — that's a separate, larger migration. It was a
**minimal capability drop-in**: bring in just `/add-adapter` and `ADAPTER-TEMPLATE.md` from the
current scaffold, and use them to re-add Shopify the new way, leaving everything else in the older
brain untouched. That scoping choice mattered — it's what made the run a fair test of the extension
path in isolation, rather than a bespoke one-off migration.

## 3. Step-by-step

**Run `/add-adapter`.** It interviews for the source's specifics — the cheap change gate, the
extraction shape, the emit target — and walks the maintainer through
[`ADAPTER-TEMPLATE.md`](../../scaffold/pipeline/ADAPTER-TEMPLATE.md) section by section.

**Fill the template's numbered sections.**
- **Cheap gate:** the cheapest call that answers "did anything change?" For Shopify: `max(updated_at)`
  across products plus resource counts, compared against the stored fingerprint.
- **Extract:** deterministic first — read counts from the source's own authoritative count field,
  never from how many items a narrative pass happened to list (this exact discipline caught a real
  bug — see §4).
- **Emit shape:** the derived files and their table-first structure.
- **Provenance:** `source` / `last-synced` / `generated-by` frontmatter on every file touched.

The filled output is [`scaffold/pipeline/examples/shopify.md`](../../scaffold/pipeline/examples/shopify.md)
in this repo — a worked example, not a built-in, kept as the reference for the shape a new adapter
should take.

**Dispatch reconciliation — the step humans miss.** Producing the new adapter file is only half the
job when it's replacing something that already existed. The old flat `pipeline/sync-shopify.md` had
to be superseded (deleted), and every place that pointed at it — the sync command's dispatch and the
pipeline README's playbook list — had to be repointed at the new `pipeline/adapters/shopify.md`. The
run also grepped the **whole brain**, not just `pipeline/`, for the old path, because a stale
reference can hide in a derived `_index.md` that nobody thinks to check when swapping an adapter.
This step is now explicit in `/add-adapter` precisely because it's the one a maintainer skims past
by default: the new file existing feels like the job is done, and it isn't.

**Live sync.** With dispatch repointed, `/sync shopify` ran against the real store. The cheap gate
did its job — it caught a genuine delta (product data had moved since the last sync) and the sync
extracted only the changed products and collections, not the whole catalog. The refreshed derived
files (`catalog.md`, `collections.md`, `store-config.md`, and their `_index.md`) came back stamped
with honest `source` / `last-synced` / `generated-by` frontmatter — provenance is not optional
scaffolding, it's what lets the next reader trust the file without re-deriving it.

**Re-run short-circuits.** Immediately running `/sync shopify` a second time, on the now-unchanged
fingerprint, stopped at the cheap gate with zero heavy calls. This is golden rule #1
(`scaffold/pipeline/README.md`) proven live, not asserted: an unchanged source costs about one
cheap call, full stop.

The work landed as a PR on the brain and was merged after human review — never a direct write to
main, per golden rule #4.

## 4. What the live run taught

A live run against a real source finds things a spec review never will. Two findings came out of an
independent review pass on the heavy extraction work, one came out of the auth path itself, and one
was a structural lesson from repointing dispatch. All four got folded back into the scaffold, which
is the actual point of running this proof against production data instead of a fixture:

- **Auth-revocation reality.** The store's on-file admin token turned out to be **revoked** — a live
  probe returned an authentication failure, not a stale-data problem. The platform had deprecated
  that class of token, and the reissue path required a developer-only OAuth exchange that wasn't a
  same-session fix. Rather than block the whole proof on that, the sync ran over a sanctioned MCP
  fallback instead, with the frontmatter honestly naming which transport actually ran and why (REST
  was blocked, not merely unused). `examples/shopify.md`'s auth section documents this two-mechanism
  shape directly: the intended REST steady-state, the working fallback, and the discipline of naming
  the real state instead of asserting the aspirational one.
- **Anti-fabrication counts.** The independent review re-checked the extracted data against the live
  store and caught a fabricated count — a variant total that had been narrated during extraction
  instead of read from the source's own count field, and was off by one. This is now a named rule in
  `ADAPTER-TEMPLATE.md` §2: counts and enumerations must come from an authoritative count field,
  never eyeballed or narrated, because a wrong number silently becomes "truth" for everyone who
  reads the derived file afterward.
- **Stale derived claims survive an adapter swap.** The same review caught a `_index.md` that still
  described the old sync method and pointed at the playbook that had just been deleted. Swapping the
  adapter file doesn't automatically fix prose that describes *how* the sync works — that has to be
  checked deliberately, which is why the whole-brain reference scan (§3) is now a required step, not
  a suggestion.
- **Dispatch reconciliation is a required step, not a nice-to-have.** Folded directly into
  `/add-adapter`'s instructions (see step 4 there) after this run — a new adapter file that isn't
  reachable through dispatch is an adapter that doesn't run.

None of this was hypothetical. It's why `CONTRIBUTING.md`'s adapter bar requires a live proof before
a new adapter is accepted — a spec-only adapter would have shipped all four of these bugs.

## 5. Your turn

The recipe generalizes to any source — Stripe, Linear, an internal API, whatever the org actually
runs on:

1. Read [`ADAPTER-TEMPLATE.md`](../../scaffold/pipeline/ADAPTER-TEMPLATE.md) end to end before
   writing anything. It's a contract: fill the skeleton, don't improvise a new shape.
2. Run `/add-adapter` and answer its interview honestly for *this* source — especially the cheap
   gate. Get that wrong and every future sync of this source does full-cost work forever.
3. Fill in the extraction and emit sections, keeping deterministic extraction and authoritative
   counts non-negotiable (golden rule #3).
4. If this replaces something that already exists — a hand-rolled script, an older flat playbook —
   do the dispatch reconciliation: supersede the old path, repoint everything that referenced it,
   and grep the whole brain, not just the pipeline directory.
5. Run it against the real, live source. Not a fixture, not a doc-only pass — a real credential
   against real data. Let a second run on an unchanged fingerprint prove the short-circuit.
6. Write up what the live run actually showed — including anything that broke or surprised you —
   and send it back per [`CONTRIBUTING.md`](../../CONTRIBUTING.md#adding-an-adapter)'s adapter bar.
   The findings that come out of *your* live run are exactly what harden the template for the next
   person, the same way this run did.
