# Setup — the guided walk from empty brain to felt value

This is the instruction set the maintainer's LLM follows to **set up a brain**, one domain at a
time. It is the builder counterpart to the two runtimes it sequences — the sync runtime
(`pipeline/`) and the canon builder (`authoring/`). The wizard **wraps** the existing commands
inline; it does not replace them, and it never relaxes their contracts.

The philosophy is depth-first: **complete one domain end-to-end and read it back before offering
the next.** Lead with a fast, derivable win; defer the slow, blank-page work (brand) until the
user is bought in.

## 0. Guard — confirm this is a brain
The concrete check is a `sources.json` at the repo root (the scaffold always emits one). If it is
absent, stop and tell the user to run `/forge` from inside a scaffolded brain — never run the loop
against an arbitrary directory.

## 1. Compute the status ladder (derive — never store)
There is **no walk-state file.** Progress is read from the brain's real materialized state on
demand, so it can never drift from reality. For each of the five catalog domains (`brand`,
`product`, `design`, `eng`, `analytics` — the à la carte catalog in `context/canon/README.md`),
derive exactly one status:

| Status | Derived from |
|---|---|
| `not-started` | no `context/canon/<domain>/` **and** no matching `sources.json` entry |
| `in-progress @ <rung>` | partial — folders exist, or canon is `status: draft`, or a source is wired but has no `.sync-state.json` fingerprint |
| `complete` | approved canon **and** (unless the domain is authored-only) a wired adapter with a `.sync-state.json` fingerprint |

`<rung>` is the next incomplete rung of the loop in §3.

## 1a. Kinds — what each domain IS (machine-readable)

Every domain folder carries an `_index.md` whose frontmatter declares its `kinds:` — the
catalog one level down (DESIGN.md §10). Routing (the synapse reader) inherits from kinds;
a brain never authors routing rules. Stamp kinds at domain creation from this table:

| Domain | Kinds emitted |
|---|---|
| `brand/` | `brand-voice`, `brand-messaging`, `naming`, `positioning`, `user-archetypes` |
| `product/` | `product-principles`, `product-roadmap`, `project-tracking` |
| `design/` | `design-principles`, `design-system`, `art-direction`, `ui-build-standards` |
| `eng/` | `repo-summaries`, `architecture-decisions`, `eng-conventions` |
| `analytics/` | `analytics`, `metric-definitions` |
| (adapter-emitted) | `site-inventory` (website), `product-catalog` (shopify/SKUs), `digital-experience` (flows/pages) |

Frontmatter shape (list syntax, within the first 20 lines):

    ---
    kinds: [brand-voice, brand-messaging, naming]
    title: Brand
    ---

A canon domain's `_index.md` lists only the kinds its docs actually cover — start with the
subset you scaffold, extend as docs land. A domain with no `kinds:` is **unclassified**: it
appears in the manifest's `unclassified` list and the reader's map, and `/sync` proposes a
classification at its next run (never silently).

## 2. Route
- If any domain is `in-progress`, offer to **resume** it at its exact next rung.
- Otherwise present the à la carte menu of `not-started` domains and **recommend the most
  derivable fast-win — `eng` or `design`** (point at a repo or Figma file, watch real facts
  populate `derived/` in minutes). **Defer `brand`** ("subjective, slow, blank-page tax — come
  back once you've felt the value"). The catalog is fixed, so unstarted domains are always
  re-offered; nothing about the user's selection is persisted.

## 3. Drive the per-domain loop inline
One seamless flow. Perform each rung yourself, reusing the instructions the sub-commands encode
(the user does not type each command). **Pause for the human at the two trust gates** — approve,
and the sync PR.

```
scaffold domain folders/templates + context/canon/<domain>/_index.md
                                    (kinds: from §1a + title:, plus a doc table)
   → ingest real material        (authoring/README.md §1)
   → interview gaps only          (authoring/README.md §2 — one question per turn)
   → draft loudly provisional     (/draft-canon — status: draft + DRAFT banner + provenance/[GAP])
   → approve (hard gate)          (/approve-canon — REFUSES while any [GAP] remains)
   → wire its one adapter         (/add-source if a built-in exists, else /add-adapter)
   → first sync                   (/sync <type> — effectively full; lands via PR)
   → READ IT BACK                 (surface the freshly-synced facts; answer a real question)
   → SHARE IT                     (§3a — print the team subscription handout, real URL filled in)
```

The **read-back is the payoff** — show what just populated `derived/` and demonstrate the brain
answering something concrete. Then run the share rung (§3a) before returning to §2 to offer the
next domain, or stop (resumable later via §1).

## 3a. Share the brain (after read-back, when a remote exists)

A brain nobody reads is worth nothing — so the moment it has something to show, hand the owner
the exact instructions their team needs. After each read-back:

1. **Check for a remote:** `git config --get remote.origin.url`. If there is none, say one
   line — "once this brain is on GitHub, I'll give you the subscription handout for your
   team" — and move on. Never print a handout with placeholder values.
2. **If a remote exists, print the handout with the real URL filled in** (substitute
   `<remote-url>` with the actual value — never leave a placeholder):

   ```
   Your team subscribes in three lines (once, ever):

     claude plugin marketplace add jrpease/brainforge
     claude plugin install synapse@brainforge
     /synapse:subscribe <remote-url>        ← run inside any Claude Code session

   Then restart the session — the brain appears in every session from then on.
   (Requires read access to <remote-url> — normal GitHub org membership.)
   ```

3. **Offer (once) to write it into the brain's README.** If `README.md`'s "Consuming this
   repo" section does not already mention `/synapse:subscribe`, offer to replace its
   placeholder subscription lines with the concrete handout above — real URL, no
   placeholders — so the instructions live in the brain itself, where anyone landing on the
   repo finds them. Idempotence check: skip the offer entirely if the README already
   contains `/synapse:subscribe` with this remote's URL.
4. This rung is **skippable and repeatable** — it costs one question at most, fires only
   when the remote first appears or the URL changed, and never blocks the domain loop.

## 4. Domain-shape adaptation
The loop flexes to each domain's lean (the catalog in `context/canon/README.md` notes which lean
derived):
- **Derived-leaning** (`eng`, `analytics`): thin canon, the adapter + sync is the star. The
  fast-win default lands here.
- **Mixed** (`product`, `design`): both halves — canon principles + a wired adapter.
- **Authored-only** (`brand`): **no adapter/sync rung**; the loop ends at approved canon and the
  read-back surfaces the approved doc itself.

## 5. Inherited guardrails — sequence them, never relax them
- **Canon four-point guardrail** (`authoring/README.md`): drafts stay loudly provisional; approve
  refuses on any `[GAP]`; brand held hardest. When approve refuses, run one interview turn to fill
  the gap, then retry — never bypass the gate.
- **Six golden rules** (`pipeline/README.md`): cheap-gate-first, REST-not-MCP, deterministic
  extraction, **every sync lands via PR**, provenance + state always stamped, extraction stays
  reference not mirrors (flag it in the PR if a derived doc outgrows its size envelope).
