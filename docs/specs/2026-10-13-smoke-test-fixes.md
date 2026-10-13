# Smoke-test fixes: subscriber permissions and the website gate

Status: built
Reviewed: 2026-10-13 — needs revision (gate half; revised below), subscribe diff ready to merge
Date: 2026-10-13

## Goal

Issue #1's public-install smoke test (run 2026-10-13, brainforge 0.15.1, synapse 0.8.0) failed in
two places. After this ships, both pass:

- **Step 6, subscribed reader.** Every brain read was refused, so the answer was honestly
  ungrounded, but ungrounded all the same. `/synapse:subscribe` granted `~/.synapse` whatever
  `SYNAPSE_HOME` said, and nothing granted the plugin's own `routing/intents.json`, which the
  brain-routing skill reads on every grounded answer. A headless run (`claude -p`) was refused
  outright. After the fix it reads the brain. An interactive session still sees one Bash prompt
  per question, because the skill's first attempt is a compound `cat` (see Open questions);
  the Read fallback then needs no prompt.
- **Step 4, a second `/sync` that should do nothing.** On choosealicense.com it re-fetched 9 to 11
  unchanged pages and committed refreshed etags. The site's CDN serves the same bytes from two
  origins with different ETags (`"6ac03420-63ba"` vs `"6ac0352c-63ba"`), so a conditional GET
  carrying the other origin's ETag returns 200, and the gate counted every 200 as changed.
  `/sync-health` then reads ⚠ behind on most runs: a warning that is permanently on. The fix
  covers flaps where the bytes are identical. A page with dynamic bytes (a nonce, a build
  timestamp) still reads changed every sync, exactly as today.

## Non-goals

- No change to the brain-routing skill. A skill change needs a routing eval run.
- No change to the other gates, or to how §2 extracts pages.
- No per-site workaround (ignoring ETags for one source, parsing an ETag's "size half"): both are
  server-specific guesses at what a content hash measures directly.

## Decisions

Jordan delegated these on 2026-10-13 ("take your recommendations"). Each row is Claude's call.

| Decision | Chose | Why | Rules out |
|---|---|---|---|
| Brain clones grant | `additionalDirectories` gets `$SYNAPSE_HOME` (absolute) when set, else `~/.synapse` | The hook clones into `$SYNAPSE_HOME`; granting anything else grants nothing | — |
| Plugin files grant | A read-only rule, `Read(//<abs>/**)`, in `permissions.allow`. For an installed copy (`…/synapse/<version>`) the rule covers the version-free parent. No `--plugin-root` → one printed line saying the rule was not written | Read-only is the least privilege the skill needs; the parent survives `claude plugin update`. A skipped grant must be visible | Granting the plugin as a working directory |
| Existing subscribers, or a changed `SYNAPSE_HOME` | Re-run `/synapse:subscribe <url>` (idempotent); it adds whatever grant is missing. The script prints the grants it holds | No migration script; the release note says so | — |
| Repo-settings template | Adds `Read(~/.claude/plugins/cache/brainforge/synapse/**)` | Same gap for tier-1 committed settings; the default config dir is the only path a committed file can name | — |
| What the website gate measures | The SHA-256 of the page body, stored per URL as `sha256` beside `lastmod`/`etag` | The ETag stood in for content and the stand-in failed; the gate already downloads the body on every non-304 | Trusting `<lastmod>` alone |
| A 304 | Skip; the fingerprint keeps the stored `sha256` (and the 304's etag, else the stored one) | Dropping the hash on a 304 would bring the flap back on the next 200 | — |
| A 2xx to the conditional GET | Unchanged when the stored `sha256` equals the body's; the fingerprint takes the response's etag and the hash | Same bytes from another origin is not a change | — |
| A changed `<lastmod>` | The gate downloads the page; if a stored `sha256` exists and equals the body's, unchanged (the fingerprint takes the new `<lastmod>`), else delta | The hash is the content; a site that stamps `<lastmod>` on every build would otherwise read behind forever by the same mechanism this fixes | Honouring `<lastmod>` over identical bytes |
| Delta URLs | Every delta URL's fingerprint is `{lastmod, etag, sha256}` from the gate's own download (the conditional GET's body when there was one, else one unconditional GET). A download that fails or is not 2xx leaves that URL `{etag: null, sha256: null}` in the delta; it never fails the whole entry | §3 then stores the gate's fingerprint verbatim, which deletes the prose merge rule. One slow page must not block a site's sync. Cost: delta pages are downloaded twice, here and in §2 | — |
| First sync (`never`) | `gate-website.sh --fingerprint <id>` downloads every sitemap URL and prints the full fingerprint (status `fingerprint`, empty delta). Website §2 runs it **before** extracting when the gate said `never`, and §3 stores that output. If it prints `not-checked`, the source is not-checked this sync | Hashing before extraction errs safe: a change in the window makes the next sync re-fetch. Hashing after would store a newer hash than the extracted content and read `unchanged` over a stale doc. A flag keeps `/sync-health` free of N downloads | Fingerprinting after §2 |
| `--fingerprint` scope | Exactly one id that exists in `websites[]`; enabled or not, synced or not | It is a measuring tool; §2 decides when to call it | — |
| State written before the fix | A stored URL with no `sha256` behaves as today: a 2xx is a delta, and that sync records the hash | Backward compatible with every existing `.sync-state.json`; one extra fetch per flapping page, once | A migration |
| Versions | brainforge 0.15.1 → 0.15.2 (gate script, `website.md` and `.brainforge/README.md` are bump paths); synapse 0.8.0 → 0.8.1 | Fixes | — |

## Open questions

- **The skill's first read attempt.** Recommendation: tell the brain-routing skill to use the Read
  tool for brain files, then run a routing eval. That removes the remaining interactive Bash
  prompt. Unresolved.

## What shipped

- `synapse/commands/subscribe.md`, `synapse/templates/product-repo-settings.md`: the grants, the
  printed `dirs:`/`read:` lines and the visible skipped-rule line. Test cases for each; mutations
  of the version-parent rule, the `SYNAPSE_HOME` read and the `//` prefix each fail it.
- `scaffold/.brainforge/gate-website.sh`: content hashing, per-page download failures, and
  `--fingerprint`. `tests/gate-website.test.sh` plus six new fixture directories; mutations
  (compare the etag, hash a constant, drop the hash on 304, let one page fail the site, make
  `--fingerprint` conditional) each fail it.
- `scaffold/pipeline/adapters/website.md`, `scaffold/.brainforge/README.md`,
  `scaffold/pipeline/README.md`: the prose and the contract.
- brainforge 0.15.2, synapse 0.8.1. Full suite 29 PASS. Live re-run in the proof.

## Where it diverged

- The first draft of the gate returned `never` before checking `--fingerprint`, which would have
  made the flag useless on exactly the source it exists for. Caught while building; a test now
  runs `--fingerprint` on a slot-less entry.
- `scaffold/pipeline/README.md`'s adapter table also named the website check; it was updated
  though Step 4 did not list it.

## Plan

### Step 1 — Subscribe grants (built; test-verified; the command path is shown live in Step 5)

Files: `synapse/commands/subscribe.md`, `synapse/templates/product-repo-settings.md`,
`tests/synapse-subscribe.test.sh`
Change: as the first four Decisions rows. The command passes `--plugin-root "${CLAUDE_PLUGIN_ROOT}"`.
Add: with no `--plugin-root`, print `no --plugin-root: plugin read rule not written`; the summary
prints the grants (`dirs:` and `read:` lines); the command prose says re-running repairs grants.
Verify: `bash tests/synapse-subscribe.test.sh` → `PASS synapse-subscribe`, with cases for the
missing-root line and the printed grants; mutations of the version-parent rule, of the
`SYNAPSE_HOME` read and of the `//` prefix each fail it.

### Step 2 — Gate hashes content

Files: `scaffold/.brainforge/gate-website.sh`
Change: `curl()` returns the body as bytes (the sitemap is decoded where it is parsed).
`download(loc, hdrs)` returns `(status, etag, sha256)`, or `None` when curl fails for that URL,
never raising for a page. Per stored URL, from the Decisions rows: equal or absent `<lastmod>` →
conditional GET; 304 → skip with the stored hash; 2xx with an equal stored hash → skip; changed
`<lastmod>` → unconditional GET, equal stored hash → skip with the new `<lastmod>`; everything
else → delta with the download's etag and hash (null on a failed or non-2xx download). New URLs →
delta, downloaded the same way. The sitemap fetch failing stays `not-checked (offline)` for the
entry. `--fingerprint <id>` downloads every sitemap URL unconditionally and emits
`status: "fingerprint"`, the full map and an empty delta; misuse (no id, more than one, unknown)
exits 1. Update the header comment.
Verify: Step 3.

### Step 3 — Gate tests

Files: `tests/gate-website.test.sh`, `tests/fixtures/gates/website/*`
Change: add a page fixture for every delta URL in the existing fixture directories (`changed/`
has none for `/pricing` and `/blog/new`), and update the cases and call counts that asserted
`etag: None` or "no fetch of the page". Stored hashes are hardcoded digests of the fixture body as
the stub serves it (each line plus `\n`), never captured from a gate run. New cases:
(a) flap: stored etag `"a-1"` and the digest of body B; the conditional GET returns 200, etag
`"b-1"`, body B → `unchanged`, fingerprint etag `"b-1"`, same hash; (b) flap, changed: body C →
delta; (c) 304 keeps the stored hash; (d) legacy: no stored `sha256`, 200 → delta, fingerprint
carries the hash; (e) changed `<lastmod>`, identical body → `unchanged`, new `<lastmod>` stored;
(f) one delta page missing from the fixtures (the stub exits 7) → that URL `{etag: null,
sha256: null}` in the delta, the entry still `changed`; (g) `--fingerprint`: every URL fetched
once, unconditionally, status `fingerprint`; (h) `--fingerprint` with no id, two ids or an
unknown id exits 1. Mutation-check: compare the etag instead of the hash; hash a constant; drop
the hash on 304. Each must fail the test.
Verify: `bash tests/gate-website.test.sh` → `PASS`.

### Step 4 — Adapter prose and the gate contract

Files: `scaffold/pipeline/adapters/website.md`, `scaffold/.brainforge/README.md`
Change: website §1 describes the hash rule and the complete delta fingerprint. §2 opens with:
when the gate said `never`, run `bash .brainforge/gate-website.sh --fingerprint <id>` first; its
fingerprint is this sync's; `not-checked` means skip the source. §3 becomes "store the
fingerprint verbatim", and the merge-exception sentence and the build-it-yourself fallback go.
State the cost (delta pages downloaded twice). README: replace line 196's website exception with
the verbatim rule, and add `fingerprint` to the contract table as "emitted only by
`gate-website.sh --fingerprint`".
Verify: `grep -n "etag: null\|set the \`etag\`\|sets the etag" scaffold/pipeline/adapters/website.md scaffold/.brainforge/README.md`
prints nothing; by eye for the prose.

### Step 5 — Versions, full suite, live re-run

Files: `.claude-plugin/plugin.json`, `synapse/.claude-plugin/plugin.json`
Change: bump both before staging.
Verify: the CI loop over `tests/*.test.sh` prints 29 PASS lines and no FAIL. Live, in the smoke
brain: copy this checkout's `gate-website.sh` into its `.brainforge/`, run
`--fingerprint marketing-site`, write its printed `fingerprint.urls` into `.sync-state.json` →
`websites["marketing-site"].urls` (a short python3 merge), then three plain gate runs each print
`"status": "unchanged"` against the live site. In the throwaway profile, reset `settings.json`
to its pre-subscribe state, run the command's own extraction of `bf-subscribe.py` with
`--plugin-root` set to the installed synapse root, and ask the step-6 eng question in a new
session. `git show HEAD:<plugin.json>` shows both versions.

### Step 6 — Proof and close issue #1

Files: `docs/proofs/public-install-smoke-test.md` (new), `docs/proofs/README.md`, `ROADMAP.md`
Change: each of issue #1's steps as PASS/FAIL with real output, the two failures, their fixes,
and the re-run. The website adapter's first live proof is part of it. The PR body closes #1.
Verify: by eye; links resolve.
