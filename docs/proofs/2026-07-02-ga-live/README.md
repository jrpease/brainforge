# GA adapter: live proof (2026-07-02)

[`scaffold/pipeline/adapters/ga.md`](../../../scaffold/pipeline/adapters/ga.md) was run against a
**real, trafficked GA4 property** on 2026-07-02. The raw derived tables from that run held a real
property's analytics output, so they are not kept here; this page records what the run proved.

This is the last Phase-2 adapter and the **first metrics / time-series source** (every prior adapter,
figma/github/website/monday/shopify, is an entity-snapshot).

## What was proven live

- **Cold-start sync.** A 90-day backfill of the Core-4 reports (traffic-overview, ecommerce,
  acquisition, top-pages). A property with no ecommerce emitted an empty-but-labeled table rather
  than a fabricated one.
- **Data-faithfulness review.** An independent reviewer **re-queried the live Data API** and matched
  the emitted tables **row-for-row**: the period session total, every acquisition channel row,
  several full spot-checked traffic days, several spot-checked top-pages rows, and the
  `.sync-state.json` trailing hashes. Zero discrepancies (the review that caught Shopify's
  fabricated count).
- **Cheap-gate short-circuit (golden rule #1, reframed for a metrics source).** An immediate second
  run of the date-bounded cheap gate (`sessions` by `date` over the trailing window) returned
  `maxDate == lastSyncedThrough` with trailing session hashes matching stored state:

  > **SHORT-CIRCUIT: no new finalized day, no restatement → ZERO heavy report calls (golden rule #1, live)**

## The two-shape delta model, exercised

- **Time-series (append-merge):** `traffic-overview.md`, `ecommerce.md`: daily rows keyed by date.
- **Rolling-window rollup (refresh-in-full):** `acquisition.md`, `top-pages.md`: trailing 28-day.
- State: `.sync-state.json → ga[<propertyId>] = { lastSyncedThrough, trailingSessionHashes }`.

## Auth path used (and why it differs from the spec)

The spec planned to prove against **Google's public GA4 demo property**. That turned out to be
**impossible**: Google's public demo properties are **API-denied**
(`429 RESOURCE_EXHAUSTED`, "This property is denied access to the API"); they are UI-only. Verified against both `Google Merch Shop` and `Flood-It!`.

Auth also could not use the planned paths: gcloud's **default** OAuth client is now **blocked** from the
`analytics.readonly` sensitive scope, and the environment's org policies blocked **service-account key
creation** and **service-account impersonation**. The working path, and the one to reach for on a
locked-down Google account, was an **own OAuth Desktop client** (self as test user) via
`gcloud auth application-default login --client-id-file=… --scopes=analytics.readonly,cloud-platform`,
authenticating as an analyst account against a **real trafficked property it had Viewer access to**.

These findings are folded into the adapter doc and `ADAPTER-TEMPLATE.md`.

## Not a live source

This is a one-time **proof**, not a registered source in any brain.
