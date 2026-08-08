---
description: Scaffold a new sync adapter for a source type that has no built-in playbook yet.
---

Create a **new adapter** by filling `pipeline/ADAPTER-TEMPLATE.md` for a source type Brainforge
doesn't ship a built-in for (e.g. Notion, Linear, a custom API). **Arguments:** `$ARGUMENTS`
(the source kind + any URL/identifier).

This is the documented extension path — consumers extend by **filling the skeleton, not
reverse-engineering style.** `pipeline/examples/shopify.md` is a worked example of the output.

Steps:
1. Read `pipeline/ADAPTER-TEMPLATE.md` — the canonical gate → extract → emit → provenance →
   command skeleton. The new adapter must honor all six golden rules (`pipeline/README.md`).
2. Interview the user for the source's specifics:
   - **Cheap change gate** — what's the cheapest fingerprint that says "nothing changed"?
     (a version field, a `max(updated_at)`, an ETag, a git SHA.) This is rule #1; get it right.
   - **Extraction** — deterministic where possible (rule #3); REST not MCP (rule #2) unless the
     data is genuinely unreachable that way (document the exception if so).
   - **Emit target** — which `context/derived/<folder>/` files, in what shape.
3. Write `pipeline/adapters/<source-type>.md` from the filled skeleton.
4. **If this replaces a legacy/flat playbook for the same source, reconcile dispatch.** An older
   brain may sync this source via a flat `pipeline/sync-<type>.md` and list it in the
   `pipeline/README.md` Playbooks table. Producing `adapters/<type>.md` is not enough on its own —
   you must also:
   - **Supersede the old playbook:** delete (or clearly mark superseded) any flat
     `pipeline/sync-<type>.md`, then **grep the WHOLE brain** for its path
     (`grep -rn 'sync-<type>' .`), not just `pipeline/` — dangling references hide elsewhere.
   - **Repoint the dispatch:** update the `.claude/commands/sync.md` reference and the
     `pipeline/README.md` Playbooks list to point at `pipeline/adapters/<type>.md`.
   - **Refresh derived `_index` files:** any `context/derived/<folder>/_index.md` that names the
     old playbook or describes the sync method/auth must be updated to match the new adapter — a
     stale "syncs via …" claim there survives an adapter swap and silently misleads readers.
5. Add a `sources.json` array + entry schema for the new type, and a `.sync-state.json` slot.
6. Note any new credential needed in `.env.example`.
7. Offer to run the first `/sync <source-type>` to prove the loop.

Do not commit credentials.
