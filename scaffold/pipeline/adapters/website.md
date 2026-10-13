# Playbook: sync the live website  (built-in adapter)

Plain HTTP — **not** the browser MCP. The MCP is the fallback only for a page that genuinely
needs rendered/JS understanding, scoped to that one URL.

## 0. Inputs
- `sources.json` → `websites[]`. Per entry: `sitemap` (absent → `<url>/sitemap.xml`), `url`,
  and `into`.
- Destination: the entry's `into:` — written `<into>` below, conventionally `web/` under the
  derived root. **No `into:` → stop; do not sync this entry and do not fall back to `web/`**
  (`pipeline/README.md` § Where a sync writes).
- `.sync-state.json` → `websites[<id>]` (per-URL lastmod + etag + sha256)

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
  `If-None-Match`) returns **304** → skip it (free). A **200** whose body hashes (SHA-256) to the
  stored `sha256` is skipped too: a CDN can serve identical bytes from two origins with different
  ETags, and the content is what "changed" means. `If-Modified-Since` is the stored `<lastmod>`
  as an HTTP-date (`Tue, 01 Sep 2026 00:00:00 GMT`), since a server ignores any other format; a
  `<lastmod>` that does not parse sends no `If-Modified-Since`.
- New URLs and changed `<lastmod>` → the gate downloads the page. A changed `<lastmod>` over
  bytes that hash to the stored value is skipped (a rebuild that bumped every date); anything
  else is the delta to fetch. A known URL with no `<lastmod>` gets the same conditional `GET`.
- The gate's `fingerprint` is `{urls: {<url>: {lastmod, etag, sha256}}}`, complete for every URL:
  a delta URL's etag and hash come from the gate's own download (so delta pages are downloaded
  twice, once here and once in §2), and are null only when that download failed or was not 2xx. One page that
  cannot be downloaded is a delta; it never makes the whole site `not-checked`.
- A slot written before hashes existed has no `sha256`: its next 200 is a delta, as before, and
  that sync records the hash.

## 2. Extract only the delta
- **When the gate said `never`, fingerprint first:** run
  `bash .brainforge/gate-website.sh --fingerprint <id>` before extracting anything. Its
  `fingerprint` is this sync's (status `fingerprint`); `not-checked` means skip the source this
  sync. Hashing before extracting errs safe: a page that changes in between is re-fetched next
  sync, never stored as current over an older extraction.
- Fetch changed URLs (every URL on a `never` source), extract title, page type, headings/structure, and key copy.
- Update `<into>site-map.md` (the inventory table) and, for significant pages, a per-page file
  in `<into>`. Refresh this site's row in `<into>_index.md`, leaving other rows alone.
## 3. Finish
- Stamp `source` / `last-synced` / `generated-by` provenance frontmatter. Exception: an existing
  `<into>_index.md`, where only `last-synced` changes (see below).
- Update `.sync-state.json` → `websites[<id>]` with the gate's `fingerprint` (its `urls` map),
  verbatim: on a `never` source, the one §2's `--fingerprint` printed.
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
