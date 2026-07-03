# Playbook: sync the live website  (built-in adapter)

Plain HTTP — **not** the browser MCP. The MCP is the fallback only for a page that genuinely
needs rendered/JS understanding, scoped to that one URL.

## 0. Inputs
- `sources.json` → `websites[]`
- `.sync-state.json` → `websites[<id>]` (per-URL lastmod + etag)

## 1. Cheap change gate (always)
```
GET <sitemap>            → list of <loc> + <lastmod>
```
- For each URL: if `<lastmod>` == stored AND a conditional `GET` (`If-Modified-Since`/
  `If-None-Match`) returns **304** → skip it (free).
- New URLs and changed `<lastmod>` → the delta to fetch.

## 2. Extract only the delta
- Fetch changed URLs, extract title, page type, headings/structure, and key copy.
- Update `context/derived/web/site-map.md` (the inventory table) and, for significant pages,
  a per-page file.

## 3. Finish
- Stamp `source` / `last-synced` / `generated-by` provenance frontmatter.
- Update `.sync-state.json` with new per-URL lastmod + etag.
- Branch + PR.

## Example
A new product page → one new `<loc>` with a fresh `<lastmod>` → fetch that single page.
Everything else returns 304 and costs nothing.
