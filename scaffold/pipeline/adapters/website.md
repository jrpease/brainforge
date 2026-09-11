# Playbook: sync the live website  (built-in adapter)

Plain HTTP — **not** the browser MCP. The MCP is the fallback only for a page that genuinely
needs rendered/JS understanding, scoped to that one URL.

## 0. Inputs
- `sources.json` → `websites[]`
- `.sync-state.json` → `websites[<id>]` (per-URL lastmod + etag)

## 0a. Size envelope  — golden rule #6

| Emitted doc | Envelope |
|---|---|
| `web/site-map.md` | ≤ 2,000 |
| `web/_index.md` | ≤ 800 |
| per-page file | ≤ 800 each |
| **domain total** | **≤ 3,000** |

**Emit the page *inventory* — path, title, page type, purpose — never the page copy.** Marketing copy
belongs in `canon/brand/`, where a human owns it and reviews it; a crawled copy of it is a second,
unowned version that will disagree with the first. A per-page file is for structure worth reasoning
about (the sections a template has, what a flow asks for), not a transcript. If the site map is
growing with every new blog post, cap it: list the sections and their counts, not every leaf URL.

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
- In `.sync-state.json`, set `"synced": true` in `websites[<id>]` and `lastFullSync` to today
  (`YYYY-MM-DD`). Disarms the session-start sync-health tripwire, which stays lit while any
  source's `synced` is `false` or `lastFullSync` is `null`.
- The emitted `_index.md` frontmatter MUST include `kinds: [site-inventory]`.
- Branch + PR.

## Example
A new product page → one new `<loc>` with a fresh `<lastmod>` → fetch that single page.
Everything else returns 304 and costs nothing.
