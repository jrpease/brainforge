# Routing — the intent table and kinds vocabulary

`intents.json` maps **intent → domain kinds**. It is the single place routing is tuned
(DESIGN.md §12): fix it here, ship a plugin update, every subscriber improves. Never vendor
it into a brain.

Kinds are the domain catalog one level down (DESIGN.md §10). Current vocabulary (v1):
`brand-voice`, `brand-messaging`, `naming`, `positioning`, `user-archetypes`,
`product-principles`, `product-roadmap`, `project-tracking`, `design-principles`,
`design-system`, `art-direction`, `ui-build-standards`, `repo-summaries`,
`architecture-decisions`, `eng-conventions`, `analytics`, `metric-definitions`,
`site-inventory`, `product-catalog`, `digital-experience`.

Growing the vocabulary is a Brainforge change (edit here + the catalog table in
`scaffold/setup/README.md` §1a + an eval case), then a synapse version bump. Adopting a kind
is a one-line brain change. Every intents.json change MUST come with a passing
`claude plugin eval` run (`evals/`) — tuning for one brain must not silently break another.
