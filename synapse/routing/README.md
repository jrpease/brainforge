# Routing — the intent table and kinds vocabulary

`intents.json` maps **intent → domain kinds**. It is the single place routing is tuned
(DESIGN.md §12): fix it here, ship a plugin update, every subscriber improves. Never vendor
it into a brain.

Kinds are the domain catalog one level down (DESIGN.md §10). Current vocabulary (v1):
`brand-voice`, `brand-messaging`, `naming`, `positioning`, `user-archetypes`,
`product-principles`, `product-roadmap`, `project-tracking`, `design-principles`,
`design-system`, `art-direction`, `ui-build-standards`, `repo-summaries`,
`architecture-decisions`, `eng-conventions`, `analytics`, `metric-definitions`,
`site-inventory`, `product-catalog`, `digital-experience`, `pricing-model`,
`company-principles`, `org-design`, `unit-context`.

**`intents.json`'s ONE-INTENT-PER-LINE LAYOUT IS A PARSING CONTRACT.** `routing/coverage.sh`
is dependency-free and derives the routable vocabulary from this file line by line — the union
of its values — to warn about kinds a brain declares that no intent points at. The session hook
(`hooks/session-start.sh`) hands off to it for that warning. Reformatting `intents.json`
(pretty-printing an array across lines, say) breaks that warning **silently**, which is the
exact failure the warning exists to catch. Same contract `gen-manifest.sh` carries on its own
output; treat it the same way.

Corollary: the routable vocabulary IS the union of `intents.json`'s values — a kind no intent
points at is unroutable whether or not it appears in the list above or in a catalog table.
Adding a kind to that list without pointing an intent at it ships a dead word.

Growing the vocabulary is a Brainforge change (edit here + the catalog table in
`scaffold/setup/README.md` §1a + an eval case), then a synapse version bump. Adopting a kind
is a one-line brain change. Every intents.json change MUST come with a passing
`claude plugin eval` run (`evals/`) — tuning for one brain must not silently break another.

If `claude plugin eval` is unavailable to you (it is gated behind org-level early access, and
that entitlement is not self-serve), run `bash synapse/evals/routing-smoke.sh` instead. It executes the
same case files with `claude -p` and scores their regex/tool_used/tool_order graders. It is a
floor, not a substitute — single run per case, no ablation arm, LLM-judge graders unscored — so
say which one you ran when you claim a passing eval.
