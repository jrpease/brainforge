# Playbook: sync the live website  (built-in adapter)

Plain HTTP — **not** the browser MCP. The MCP is the fallback only for a page that genuinely
needs rendered/JS understanding, scoped to that one URL.

## 0. Inputs
- `sources.json` → `websites[]`. Per entry: `sitemap` (absent → `<url>/sitemap.xml`), `url`,
  and `into`.
- Destination: the entry's `into:` — written `<into>` below, conventionally `web/` under the
  derived root. **No `into:` → stop; do not sync this entry and do not fall back to `web/`**
  (`pipeline/README.md` § Where a sync writes).
- `.sync-state.json` → `websites[<id>]` (per-URL lastmod + etag)

## 0a. Size envelope  — golden rule #6

Paths are relative to `<into>`.

| Emitted doc | Envelope |
|---|---|
| `site-map.md` | ≤ 2,000 |
| `_index.md` | ≤ 800 |
| per-page file | ≤ 800 each |
| **domain total** | **≤ 3,000** |

**Emit the page *inventory* — path, title, page type, purpose — never the page copy.** Marketing copy
belongs in `canon/brand/`, where a human owns it and reviews it; a crawled copy of it is a second,
unowned version that will disagree with the first. A per-page file is for structure worth reasoning
about (the sections a template has, what a flow asks for), not a transcript. If the site map is
growing with every new blog post, cap it: list the sections and their counts, not every leaf URL.

## 1. Cheap change gate (always)
**The gate is `.brainforge/gate-website.sh`; this section documents what it does.** `/sync` and
`/sync-health` run the script and route on the JSON it prints (`.brainforge/README.md` § Gate
scripts). Never run the call below by hand, even when the script cannot run: that source is
`not-checked`.

```
GET <sitemap>            → list of <loc> + <lastmod>
```
- For each URL: if `<lastmod>` == stored AND a conditional `GET` (`If-Modified-Since`/
  `If-None-Match`) returns **304** → skip it (free). `If-Modified-Since` is the stored `<lastmod>`
  as an HTTP-date (`Tue, 01 Sep 2026 00:00:00 GMT`), since a server ignores any other format; a
  `<lastmod>` that does not parse sends no `If-Modified-Since`.
- New URLs and changed `<lastmod>` → the delta to fetch. A known URL with no `<lastmod>` gets the
  same conditional `GET`.
- The gate's `fingerprint` is `{urls: {<url>: {lastmod, etag}}}`. A skipped URL carries its stored
  etag, or the one the 304 returned. A delta URL carries its new `<lastmod>` and `etag: null`,
  because the gate never fetched the page.

## 2. Extract only the delta
- Fetch changed URLs, extract title, page type, headings/structure, and key copy.
- Update `<into>site-map.md` (the inventory table) and, for significant pages, a per-page file
  in `<into>`. Refresh this site's row in `<into>_index.md`, leaving other rows alone.
## 3. Finish
- Stamp `source` / `last-synced` / `generated-by` provenance frontmatter. Exception: an existing
  `<into>_index.md`, where only `last-synced` changes (see below).
- Update `.sync-state.json` → `websites[<id>]` with the gate's `fingerprint` (its `urls` map),
  then set the `etag` of each URL §2 fetched from that fetch's response. That merge is the one
  exception to storing the gate's fingerprint verbatim: the gate left those etags `null`. When
  the gate gave no fingerprint (`never`), build the same map from the sitemap and §2's fetches.
- In `.sync-state.json`, set `"synced": true` in `websites[<id>]` and `lastFullSync` to today
  (`YYYY-MM-DD`). Disarms the session-start sync-health tripwire, which stays lit while any
  source's `synced` is `false` or `lastFullSync` is `null`.
- **Never write `kinds:`.** `<into>_index.md` follows the index rule in `pipeline/README.md`
  § Where a sync writes: if it exists, change only `last-synced` in its frontmatter; if it does
  not, create it with provenance and `title:` but no `kinds:`. `/sync` then proposes kinds for a
  human to confirm (this source
  usually proposes `site-inventory`).
- Branch + PR.

## Example
A new product page → one new `<loc>` with a fresh `<lastmod>` → fetch that single page.
Everything else returns 304 and costs nothing.
