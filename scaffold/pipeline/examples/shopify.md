# Playbook: sync the Shopify store  (worked extension example)

> **This file is an example, not a built-in.** It shows what `/add-adapter` produces when you
> extend Brainforge to a source it doesn't ship — here, a Shopify store. It fills
> `pipeline/ADAPTER-TEMPLATE.md` and honors the six golden rules. Use it as the reference for writing
> your own adapter; copy the *shape*, not the Shopify specifics.

Covers store catalog, collections, and store config. Auth: see below (Shopify-specific).

## Auth — read this first
This adapter accepts **two** mechanisms (a deliberate, Shopify-specific exception to golden
rule #2's "REST-not-MCP"). Note the *current* state below — it's why the exception is live:

1. **Intended steady-state — Admin REST API.** `SHOPIFY_ADMIN_TOKEN` in `.env` (`read_products`
   scope), base URL `https://<shopDomain>/admin/api/<apiVersion>/`. This is the path for
   *unattended/scheduled* syncs. **Currently blocked:** Shopify **deprecated legacy custom-app
   tokens on 2026-01-01**, and this store's stored token was **REVOKED** (a live probe of
   `shop.json` returns **HTTP 401**). To restore REST, mint a fresh token via the **Dev Dashboard
   OAuth token-exchange** — the new apps only expose a Client ID + secret (`shpss_…`), not a
   one-click Admin token, so this is a developer task. Once a valid token exists, REST is default.
2. **Working fallback (used for the real sync) — connected Shopify MCP** via `graphql_query`.
   Sanctioned for bootstrap and human-triggered re-syncs, and the transport that actually ran here
   while REST is blocked. Same extraction shape, same derived output as REST.

Whichever is used, the extraction shape and derived output are identical.

*(Example note: copy the two-mechanism **shape** and the "name the real state, don't paper over a
broken path" discipline — not these Shopify-specific token/revocation details.)*

## 0. Inputs
- `sources.json` → `shopify[]`. Per entry: `shopDomain` + `apiVersion` (Auth, above), `extract`
  (which of the three §2 resources to pull; absent → all three), and `into`.
- Destination: the entry's `into:` — written `<into>` below, conventionally `shopify/` under the
  derived root. **No `into:` → stop; do not sync this entry and do not fall back to `shopify/`**
  (`pipeline/README.md` § Where a sync writes).
- `.sync-state.json` → `shopify[<id>]` (catalog fingerprint + per-resource counts)

## 0a. Size envelope  — golden rule #6

Paths are relative to `<into>`.

| Emitted doc | Envelope |
|---|---|
| `catalog.md` | ≤ 4,000 |
| `collections.md` | ≤ 1,500 |
| `store-config.md` | ≤ 1,000 |
| `_index.md` | ≤ 800 |
| **domain total** | **≤ 6,000** |

**A catalog is the honest growth case: it scales with the store, not with the extraction.** Hold the
line by changing the *unit* rather than the envelope. Under roughly 100 SKUs, a row per product with
its variants is fine. Past that, collapse variants to a count and a price range; past a few hundred,
group by product type and collection and name only what is distinctive. Never emit inventory
quantities, order data, or customer data — those are live state Shopify owns, and a snapshot of them
is wrong the moment it lands.

## 1. Cheap change gate (always)
```
products    → max(updated_at) + count  (REST: GET /products.json?fields=id,updated_at&limit=250, paginate;
                                        MCP fallback: graphql_query products(first,sortKey:UPDATED_AT))
collections → max(updated_at) + count  (REST: /custom_collections.json + /smart_collections.json;
                                        MCP fallback: graphql_query collections)
shop        → shop.updated_at          (REST: GET /shop.json; MCP fallback: graphql_query shop)
```
- Compare `max(updated_at)` and resource counts against the stored fingerprint.
- All equal → **stop.** Nothing changed.
- Else → the resources whose `updated_at` moved (or count changed) are the delta.

## 2. Extract only the delta
Only the resources named in the entry's `extract` (`products`, `collections`, `shop-config`).
- **Products** → `<into>catalog.md`: per-SKU title, handle, status, product
  type, price range, variants (SKU/option/price), and image URLs (link, do **not** commit
  binaries). Deterministic table first; keep any prose factual and short. **Read the variant
  count from `variantsCount.count` (or REST's paged count) — never from how many variants a
  narrative pass listed. A made-up count becomes "truth."**
- **Collections** → `<into>collections.md`: title, handle, description,
  rule/membership summary.
- **Shop config** → `<into>store-config.md`: name, domains, currency, plan,
  policies, and brand-relevant metafields.
- Cross-link SKUs to Figma dielines where handles match, looking in the `<into>` of each enabled
  `figma[]` entry whose `extract` includes `frames`. No match, no link.

## 3. Finish
- Stamp `source` / `last-synced` / `generated-by` frontmatter on each file (except an existing
  `<into>_index.md`, where only `last-synced` changes; see below). Make `generated-by`
  **name the transport that actually ran**, so provenance stays honest — e.g.
  `pipeline/examples/shopify.md (Shopify MCP graphql_query; REST token revoked 2026-01-01)` for
  the fallback, or `pipeline/examples/shopify.md (Shopify Admin REST)` once a token exists.
- Update `.sync-state.json` → `shopify[<id>]` with new `max(updated_at)` + counts.
- In `.sync-state.json`, set `"synced": true` in `shopify[<id>]` and `lastFullSync` to today
  (`YYYY-MM-DD`). Disarms the session-start sync-health tripwire, which stays lit while any
  source's `synced` is `false` or `lastFullSync` is `null`.
- **Never write `kinds:`.** `<into>_index.md` follows the index rule in `pipeline/README.md`
  § Where a sync writes: if it exists, change only `last-synced` in its frontmatter; if it does
  not, create it with provenance and `title:` but no `kinds:`. `/sync` then proposes kinds for a
  human to confirm (this source
  usually proposes `product-catalog`).
- Branch + PR.

## Never
- **No orders, no customers, no PII.** This is brand/product source-of-truth, not a CRM mirror.
- No raw image binaries committed — store CDN URLs (or Git-LFS).

## Reminder: Shopify owns its own truth
This is a *read-only snapshot for cross-team context*. Edits to the catalog happen in Shopify
admin, then flow here on the next sync — never the reverse.

---

### `sources.json` entry shape (the new array this example adds)
```json
{
  "id": "<store-id>",
  "label": "Shopify store (catalog, collections, store config)",
  "shopDomain": "<store>.myshopify.com",
  "apiVersion": "2026-04",
  "extract": ["products", "collections", "shop-config"],
  "into": "context/derived/shopify/",
  "enabled": true,
  "cadence": "weekly",
  "acceptedSize": [
    { "doc": "catalog.md", "tokens": 5200, "since": "<YYYY-MM-DD>", "why": "<why this is fine>" }
  ]
}
```
