# Playbook: sync GA (Google Analytics 4)  (built-in adapter)

Covers: a marketing-analytics snapshot of a GA4 property — daily traffic + engagement, acquisition by
channel, top pages, and ecommerce performance. Auth: a **service-account JSON key**
(`GOOGLE_APPLICATION_CREDENTIALS` in `.env`, the SA email added as a property Viewer) is the unattended
steady-state path — **where you own the property and org policy allows SA keys**. Where you only have
*viewer* access, or your org blocks SA keys/impersonation (both common now), authenticate **as yourself
with your own OAuth Desktop client**: `gcloud auth application-default login --client-id-file=<client_secret.json>
--scopes=https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform`.
gcloud's **default** client is now **blocked** from the sensitive `analytics.readonly` scope, so a
personal/own OAuth client (self added as a Test user) is required — the default `gcloud auth
application-default login` no longer works for GA. **Google's public GA4 demo properties are API-denied**
(`429 RESOURCE_EXHAUSTED`, "denied access to the API") — they cannot back a Data-API proof; point at a
real trafficked property. GA4 **Data API**
(`https://analyticsdata.googleapis.com/v1beta/properties/<id>:runReport`), Bearer token in the
`Authorization` header — the cheap direct HTTP endpoint golden rule #2 means (the heavy MCP is still
avoided).

**This is the first metrics / time-series source.** A metrics source *always* changes — a new day
exists, and GA restates recent days as they finalize — so the cheap gate is **date-bounded**, not a
whole-source fingerprint (§1), and the delta is a **date window** (§2).

## 0. Inputs
- `sources.json` → `ga[]` (filter `enabled: true`, or the one `propertyId` passed as arg). Locator
  field: `propertyId` (numeric GA4 property id). Per-source config: `lookbackDays` (default 3 —
  trailing days re-checked for restatement), `backfillDays` (default 90 — cold-start window),
  `rollupDays` (default 28 — the rolling window for the refresh-in-full reports).
- `.sync-state.json` → `ga[<propertyId>]` =
  `{ "lastSyncedThrough": "<YYYY-MM-DD>", "trailingSessionHashes": { "<YYYYMMDD>": <sessions>, … } }`
  (the last `lookbackDays` of the sessions-by-date series).

## 0a. Size envelope  — golden rule #6

| Emitted doc | Envelope |
|---|---|
| `ga/_index.md` | ≤ 1,000 |
| `ga/traffic-overview.md` | ≤ 1,500 |
| `ga/acquisition.md` | ≤ 1,000 |
| `ga/top-pages.md` | ≤ 1,500 |
| `ga/ecommerce.md` | ≤ 1,000 |
| **domain total** | **≤ 5,000** |

**A time series is the one emit shape that grows on its own, so bound it explicitly.** The
append-merge series must stay inside the configured trailing window: when `traffic-overview.md` or
`ecommerce.md` reaches its envelope, roll the days that have fallen out of the window into
period aggregates (month totals, period-over-period deltas) and drop the rows, rather than letting
history accumulate a row at a time. Rollups (`acquisition.md`, `top-pages.md`) refresh in full and
stay capped by their own top-N. GA answers "what happened on 14 March" better than a file can; the
brain's job is the shape and the direction of travel.

## 1. Cheap change gate (always)  — golden rule #1  (metrics reframe)
A GA report carries no ETag/version and always "changes," so the cheapest "did anything change?" probe
is a **tiny report**: `sessions` by `date` over the trailing window
`[lastSyncedThrough − lookbackDays, yesterday]`.
```
POST .../properties/<propertyId>:runReport     header: Authorization: Bearer <token>
{ "dateRanges":[{"startDate":"<lastSyncedThrough−lookbackDays>","endDate":"yesterday"}],
  "dimensions":[{"name":"date"}], "metrics":[{"name":"sessions"}],
  "orderBys":[{"dimension":{"dimensionName":"date"}}] }
```
- Fingerprint = `(maxDate, {date: sessions} across the window)`. If `maxDate == lastSyncedThrough`
  **and** every day's sessions matches `trailingSessionHashes` → **stop. No new finalized day, no
  restatement. Zero heavy report calls.** (This is the golden-rule-#1 short-circuit, reframed for a
  metrics source.)
- Else → the days that are **new** (`date > lastSyncedThrough`) or **restated** (sessions differ from
  stored) define the **delta window** `[min(changed date), yesterday]`.
- **Freshness boundary = yesterday (T‑1):** "today" is always partial in GA — never include it in the
  stable tables. "Yesterday" is in the **property's reporting time zone** (pin it live — see `Never`).
- **First run** (no stored state): the delta window is the whole `backfillDays` (cold-start backfill).

## 2. Extract only the delta
Re-pull the reports **only for the delta window**, in two shapes:

- **Time-series (append-merge)** — `traffic-overview`, `ecommerce`: daily rows keyed by `date`. Replace
  the file's overlapping trailing rows with the re-pulled window and append new days; rows older than
  the window are left **byte-stable** (never re-fetched or rewritten — *work scales with the delta*).
  - `traffic-overview`: dims `[date]`, metrics `[sessions, totalUsers, newUsers, engagedSessions,
    averageSessionDuration]`.
  - `ecommerce`: dims `[date]`, metrics `[ecommercePurchases, purchaseRevenue]`; AOV =
    `purchaseRevenue / ecommercePurchases` (computed; blank when purchases = 0).
- **Rolling-window rollup (refresh-in-full)** — `acquisition`, `top-pages`: no natural per-day delta;
  when the gate trips, re-pull the whole trailing `rollupDays` window and overwrite the file (small —
  full refresh is fine).
  - `acquisition`: dateRange `[<rollupDays>daysAgo, yesterday]`, dims `[sessionDefaultChannelGroup]`,
    metrics `[sessions, totalUsers, conversions]`, order `sessions` desc.
  - `top-pages`: dateRange `[<rollupDays>daysAgo, yesterday]`, dims `[pagePath]`, metrics
    `[screenPageViews, averageSessionDuration]`, order `screenPageViews` desc, `limit: 50`.

- **Deterministic (golden rule #3):** every number is read from the `runReport` response's
  `rows[].metricValues` (and `dimensionValues` for the keys) — **never eyeballed or narrated.** A
  fabricated metric becomes "truth" downstream.
- **Metric-name caveat (pin live):** GA renamed `conversions` → `keyEvents` (2024–25). If `conversions`
  errors on the property, use `keyEvents`. Confirm every metric/dimension name against the live property
  on the first run and harden this list from what the API accepts.
- **Transport (golden rule #2):** GA4 Data API `runReport` over HTTPS with a Bearer token — the cheap
  direct endpoint. Not an MCP.
- **Emit to:** `context/derived/ga/…` — one file per report, table-first:
  - `traffic-overview.md` — date · sessions · total users · new users · engaged sessions · avg session duration
  - `ecommerce.md` — date · purchases · revenue · AOV
  - `acquisition.md` — channel · sessions · users · conversions   *(trailing `rollupDays`)*
  - `top-pages.md` — page path · views · avg session duration   *(trailing `rollupDays`, top 50)*
  - `_index.md` — property id · date range covered · per-report last-synced · `lookbackDays`/`backfillDays`/`rollupDays` in effect
## 3. Finish  — golden rule #5
- Stamp `source` / `last-synced` / `generated-by` on every file touched.
- Update `.sync-state.json` → `ga[<propertyId>]` = `{ lastSyncedThrough: <yesterday>,
  trailingSessionHashes: {last lookbackDays of the sessions-by-date series} }`.
- Set `.sync-state.json` → `lastFullSync` to today (`YYYY-MM-DD`). Disarms the session-start
  sync-health tripwire, which stays lit while that field is `null`.
- The emitted `_index.md` frontmatter MUST include `kinds: [analytics]`.
- **Branch + PR — never push to main directly (golden rule #4).**

## Never
- **No user-level or re-identifying data** — aggregate metric/dimension rows only. No user/client IDs;
  no small-cohort `city`/`age`/`gender` combinations that could re-identify an individual.
- **No "today" partial rows** — stable tables run through **yesterday (T‑1)** in the property's
  reporting time zone. That zone is in every `runReport` response as `metadata.timeZone` (and the
  revenue currency as `metadata.currencyCode`) — read it from there, don't assume, so "yesterday" is
  unambiguous.
- **Never fabricate a row for an empty report** — a report that returns 0 rows (e.g. `ecommerce` on a
  property with no ecommerce events) is emitted with headers + a one-line "no rows in range" note,
  never an invented row. (Proven live: a real property returned 0 ecommerce rows over 90 days.)
- No raw exports/binaries — derived tables only.

## Reminder: the source owns its own truth
This is a *read-only snapshot for cross-team context*. Analytics live in GA; they flow here on the next
sync — never the reverse.
