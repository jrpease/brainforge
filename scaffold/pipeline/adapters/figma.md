# Playbook: sync Figma  (built-in adapter)

Covers design tokens, component inventory, and frames/dielines.
Uses the **Figma REST API** (`FIGMA_TOKEN` from `.env`) for the cheap change gate, styles, and
frame images. Two things need the **Figma Console MCP Desktop Bridge** instead — the two
documented exceptions to golden rule #2, each because REST genuinely cannot reach the live truth:
1. **Variables/tokens** — the Variables REST endpoint is Enterprise-only (403 on other plans).
2. **Live component inventory** — REST returns the *published-library* snapshot, which diverges
   from the live document until someone re-publishes.

(See "Design tokens" and "Components" in §2.)

## 0. Inputs
- `sources.json` → `figma[]` (filter `enabled: true`, or the one passed as arg). Per entry:
  `fileKey`, `extract` (§1–2), and `into`.
- Destination: the entry's `into:` — written `<into>` below, conventionally `design-system/` under
  the derived root. **No `into:` → stop; do not sync this entry and do not fall back to
  `design-system/`** (`pipeline/README.md` § Where a sync writes).
- `.sync-state.json` → `figma[<fileKey>]`

## 0a. Size envelope  — golden rule #6

One Figma file can feed several domains (design system, flows, dielines): register one entry per
domain, each with its own `into:` and `extract`. Paths are relative to each entry's `<into>`.

| Emitted doc | Envelope |
|---|---|
| `tokens.json` | ≤ 1,500 |
| `figma-library.md` (style + component-set inventory) | ≤ 2,500 |
| `_index.md` | ≤ 2,000 |
| **per-domain total** | **≤ 5,000 each** |

**Emit reference, not a mirror.** For a design file that means page and frame *structure* with node
IDs and image links, style and component-set *names*, token keys and values. It does **not** mean
per-layer trees, per-variant property dumps, or a bundled icon set enumerated one icon at a time — an
icon library alone can run to well over a thousand components, so record the count and the containing
frame instead. If a doc approaches its envelope, drop to counts plus a link to the Figma node —
an inventory grows with the library, so aggregate rows rather than splitting one doc into several,
which only hides the growth from the envelope.

## 1. Cheap change gate (always)
```
GET https://api.figma.com/v1/files/:fileKey?depth=1
  → read `version` and `lastModified`
```
- If `version` == stored version → **stop. Nothing changed.** (zero heavy calls)
- Entries sharing a `fileKey` share its state slot: run the gate once, and if it trips, extract
  for **every** enabled entry with that `fileKey` before writing the new `version`. Otherwise the
  first entry's write makes the gate report "unchanged" for the rest. So `/sync figma <id>` widens
  to every entry sharing that `fileKey`; say so in the PR body.
- An enabled entry whose `<into>` holds none of its output yet (newly added on an already-synced
  `fileKey`) extracts regardless of the gate. The shared slot's version says nothing about it.
- Else → the file changed. Re-extract the configured `extract` types for this source
  (`variables` / `styles` / `components` / `frames`), each gated by its own cheap check in §2.
  `.sync-state.json` stores a **file-level** `version` per source — not per-node hashes — so the
  gate is "this file changed; which of its sub-resources moved?", resolved by the per-resource
  checks below (token-export merge diff, style/component counts), not by a node-id walk. Keep
  state file-level: it's the honest, cheap contract.

## 2. Extract only the delta

**Design tokens (deterministic, preferred path):**
- Figma variables → DTCG JSON at `<into>tokens.json`. Deterministic —
  no LLM guessing at hex values.
- **Where to read the variables from (this matters):**
  - The Variables **REST** endpoint (`GET /v1/files/:fileKey/variables/local`) is
    **Enterprise-only** — on non-Enterprise plans it returns **HTTP 403 (requires
    `file_variables:read`)**. Do **not** treat that 403 as a sync failure; it's expected.
  - **Fallback (works on any plan):** pull variables through the **Figma Console MCP Desktop
    Bridge**. Requires the target file open in the Figma **desktop** app with the bridge plugin
    connected. This is the documented exception to golden rule #2: REST genuinely cannot reach
    this data. Concretely:
    1. Probe the bridge with `figma_get_status` (`probe: true`). If it's not connected, that's a
       *setup* failure, not a data failure — tell the user to open the file in Figma desktop and
       run the bridge plugin; don't write a half-empty `tokens.json`.
    2. Run `figma_export_tokens` with `format: "dtcg"`, `outputPath: "<into>tokens.json"`,
       and `strategy: "merge"`. This tool **replaces** the old "export → transform → Style
       Dictionary" hop — it writes the DTCG file directly, and `merge` writes **only the tokens
       that changed since the last sync** (golden rule #1, enforced inside the tool). Use
       `strategy: "dry-run"` first if you want to preview the delta before touching the file.
    3. It writes to disk rather than dumping the whole variable set into context, so it does
       **not** violate the "MCP is token-hungry" concern behind golden rule #2.
    - (`figma_get_variables` follows the same resolution order — Desktop Bridge → Variables REST →
      Styles API — and is the read-only counterpart if you need the values in context rather than
      on disk. Prefer `figma_export_tokens` for the sync write.)
  - **Styles:** the `/styles` REST endpoint works on any plan and reflects the live file — use
    REST for the text/effect style inventory.
  - **Components — REST shows the *published library*, not the live document.** The
    `/components` and `/component_sets` REST endpoints return what the file last **published** to
    the team library, which **diverges from the live document** whenever someone has edited
    components without re-publishing (e.g. a dedup cleanup that hasn't been pushed to the library
    yet). REST will happily report stale, pre-cleanup counts. So for a **truthful** component-set
    inventory, read it **live through the MCP Desktop Bridge** (`figma_get_design_system_summary`
    for set/category counts, `figma_search_components` to enumerate) — this is a **second
    sanctioned bridge exception**, same rationale as variables: REST cannot reach the live truth.
    If the bridge is unavailable, you may fall back to REST **but must stamp the count as
    "published-library snapshot, may lag the live file."**

**Components:**
- Track the **component-set** inventory (the stable, meaningful unit), read **live via the
  bridge**. Raw variant totals are counting-method-dependent (the summary tool, the REST
  published view, and a manual variant tally can each give a different number) — never treat a
  shifted variant count alone as a content change; the set list is the signal. Update the
  per-set rows in the Figma library inventory file (name, frame, variants, and — if a repo is
  synced — whether it maps to a code component). State explicitly whether counts are bridge-live
  or a REST-published snapshot.

**Frames / dielines:**
- For each changed frame: `GET /v1/images/:fileKey?ids=<node>&format=png` → store the **export
  URL as a link** (or Git-LFS the file), never a committed binary; update this file's rows in
  `<into>_index.md`, leaving other rows alone.
## 3. Finish
- Stamp `last-synced` (today) + `source` + `generated-by` on every file touched. Exception: an
  existing `<into>_index.md`, where only `last-synced` changes (see below).
- Update `.sync-state.json` → `figma[<fileKey>]` with the new file-level `version` +
  `lastModified`. A version bump with no material change to tracked resources (variables, styles,
  component sets) is a legitimate outcome: re-stamp the fingerprint, note "no content change,"
  and skip the rewrite — the gate flagging an edit does not oblige an extraction.
- In `.sync-state.json`, set `"synced": true` in `figma[<fileKey>]` and `lastFullSync` to today
  (`YYYY-MM-DD`). Disarms the session-start sync-health tripwire, which stays lit while any
  source's `synced` is `false` or `lastFullSync` is `null`.
- **Never write `kinds:`.** `<into>_index.md` follows the index rule in `pipeline/README.md`
  § Where a sync writes: if it exists, change only `last-synced` in its frontmatter; if it does
  not, create it with provenance and `title:` but no `kinds:`. `/sync` then proposes kinds for a
  human to confirm (this source
  usually proposes `design-system`, or `digital-experience` for an entry that syncs frames/flows).
- Branch + PR. Do not push to main directly.

## Never
- No committed image binaries — links or Git-LFS only.

## Cost note
A file with no changes costs **one** cheap REST call. Only genuinely-changed nodes incur
extraction. This is the whole point — never let a one-frame change trigger a full re-pull.
