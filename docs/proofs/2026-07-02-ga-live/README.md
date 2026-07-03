# GA adapter — live proof artifact (2026-07-02)

Worked output of [`scaffold/pipeline/adapters/ga.md`](../../../scaffold/pipeline/adapters/ga.md) run
against a **real, trafficked GA4 property** on 2026-07-02. The derived tables here are the adapter's
actual output; the property identity and page paths are **redacted** (property id/name → `REDACTED`,
page paths → `/path-NN`) because Brainforge may go public — all **numbers and table shapes are the
real, faithful output**, unchanged.

This is the last Phase-2 adapter and the **first metrics / time-series source** (every prior adapter —
figma/github/website/monday/shopify — is an entity-snapshot).

## What was proven live

- **Cold-start sync** — a 90-day backfill of the Core-4 reports. Total **119,870 sessions** over 90
  days (2026-04-03 … 2026-07-01). Row counts: traffic-overview **90**, ecommerce **0** (property has no
  ecommerce — emitted empty-but-labeled, not fabricated), acquisition **6** channels, top-pages **50**.
- **Data-faithfulness review** — an independent reviewer **re-queried the live Data API** and matched
  the emitted tables **row-for-row**: the 90-day session total, every acquisition channel row, three
  full spot-checked traffic days, three spot-checked top-pages rows, and the `.sync-state.json`
  trailing hashes. Zero discrepancies (the review that caught Shopify's fabricated count).
- **Cheap-gate short-circuit (golden rule #1, reframed for a metrics source)** — an immediate second
  run of the date-bounded cheap gate (`sessions` by `date` over the trailing window) returned
  `maxDate == lastSyncedThrough` (2026-07-01) with trailing session hashes matching stored state:

  > **SHORT-CIRCUIT — no new finalized day, no restatement → ZERO heavy report calls (golden rule #1, live)**

## The two-shape delta model, exercised

- **Time-series (append-merge):** `traffic-overview.md`, `ecommerce.md` — daily rows keyed by date.
- **Rolling-window rollup (refresh-in-full):** `acquisition.md`, `top-pages.md` — trailing 28-day.
- State: `.sync-state.json → ga[<propertyId>] = { lastSyncedThrough: 2026-07-01, trailingSessionHashes:
  {…last 3 days…} }`.

## Auth path used (and why it differs from the spec)

The spec planned to prove against **Google's public GA4 demo property**. That turned out to be
**impossible**: all Google public demo properties are **API-denied** by Google
(`429 RESOURCE_EXHAUSTED`, "This property is denied access to the API") — they are UI-only. Verified
against both `Google Merch Shop` and `Flood-It!`.

Auth also could not use the planned paths: gcloud's **default** OAuth client is now **blocked** from the
`analytics.readonly` sensitive scope, and the environment's org policies blocked **service-account key
creation** and **service-account impersonation**. The working path — and the one to reach for on a
locked-down Google account — was an **own OAuth Desktop client** (self as test user) via
`gcloud auth application-default login --client-id-file=… --scopes=analytics.readonly,cloud-platform`,
authenticating as the analyst account against a **real trafficked property they were granted Viewer
access to**.

These findings are folded into the adapter doc and `ADAPTER-TEMPLATE.md` (see the hardening commit) and
the session handoff.

## Not a live source

This is a one-time **proof artifact**, not a registered source in any brain. It is committed as
evidence that the adapter works end-to-end against real metrics data.
