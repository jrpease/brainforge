# Executable sync checks

Status: built
Date: 2026-10-07

## Problem

There is no way to check that the sync layer is correct, because two of its load-bearing checks
exist only as prose that the model carries out:

- **Cheap gates.** Every adapter's §1 describes a call (`curl` to Figma, a GraphQL POST to
  Monday, `git diff` for GitHub, and so on). `/sync`, `sync-all.md` and `/sync-health` tell the
  model to "run the adapter's gate", so the model rebuilds the call from prose each time. Nothing
  tests it. Monday's gate also has a known hole: `monday.md` §1 says a pure in-place column edit
  may not bump `updated_at`, so such an edit could slip past the gate.
- **Golden rule 6.** `scaffold/.claude/commands/sync.md` (step 3) asks the model to resolve each
  doc's envelope three ways, compare it against `$PREV`, apply 3× growth and domain totals, and
  print `⚠ rule-6:` lines. That is arithmetic done in prose.

"Phase D" is the fourth group on the priority list Jordan approved on 2026-10-07, in the
conversation that produced this spec; it is not yet in the repo. Its source is a critique of the
sync layer: correctness is unverifiable while gates and envelope arithmetic are model-run prose.
Step 13 records it in `ROADMAP.md` as a section after **Field hardening**.

The other two Phase D items are the same problem from other angles:

- **Routing evals.** Every case makes the brain the cwd. A subscribed reader sees only the
  synapse hook's map, which has no file list. `stranded-file/case.yaml` says outright that no
  case covers that. Six of the 13 intents in `synapse/routing/intents.json` have no case: naming
  (3), design or art direction (4), metrics (7), engineering conventions (8), site or catalog (9)
  and users or audience (10). Four of those six (7, 8, 9, 10) have no fixture domain to route to.
  `synapse/routing/README.md` names `claude plugin eval` as the required runner, but that runner
  is gated behind early access.
- **Session hooks.** `scaffold/.claude/settings.json` holds four inline hook one-liners. It is a
  `runtime.bump` file, so when an owner adds a permission or a hook of their own, `/upgrade`
  flags the file `FLAG-MODIFIED`.

**A finding that changes item 4.** Moving the hooks into a script is not enough by itself to stop
the flags. `commands/upgrade.md`'s classifier flags `FLAG-MODIFIED` whenever the brain's bytes
differ from the manifest baseline (`B != M`), whether or not upstream changed. Its own text says
so: a `NO-UPSTREAM-CHANGE` file "still flags, because the classifier compares bytes". After
re-baselining, an owner-edited `settings.json` still differs from shipped, so it flags on every
upgrade forever. Open question 1 covers this.

## Goal

When this ships, each built-in adapter's cheap gate and the rule-6 envelope check are scripts
with offline tests. `/sync` and `/sync-health` run those scripts and pass on what they print
instead of improvising. A subscribed-reader routing case exists, and every one of the 13 intents has a case.
The README names a runner that anyone can actually use. Session hooks live in a shipped script,
and an owner-edited `settings.json` stops being re-flagged on upgrades where it did not change
upstream.

## Non-goals

- Live verification against real sources. It is backlogged (D2). The checks it must make are
  listed under **Live checks (backlogged)**.
- The Shopify example adapter (`pipeline/examples/shopify.md`). It is not a built-in, so it gets
  no gate script. Custom adapters may ship one but are not required to.
- Scripting extraction (§2), state writes (§3), or anything else past the gate.
- Applying the registry's semantic `summarize` categories (`routes`, `components`, …) in a script.
  Only `.brainforge-source.yml`, which is glob-shaped, is applied mechanically.
- GA's `conversions` → `keyEvents` metric uncertainty. That is extraction, not the gate.
- New dependencies. Brains stay on bash, python3 stdlib, git and curl (`sync-contract.sh` already
  requires python3). The GA gate also uses `gcloud`, which `ga.md` already requires for auth.
- New `.env` variables. Every gate reads only credentials `.env.example` already names.

## Decisions

| # | Decision | Made by |
|---|---|---|
| D1 | Do Phase D items 1–4 (executable cheap gates, a scripted rule-6 check, subscribed-path routing eval plus intent coverage plus the README runner fix, and session hooks moved into a script with a migration story), driven by the critique that sync correctness is unverifiable while gates and envelope arithmetic are model-run prose. | Jordan, 2026-10-07 |
| D2 | Move forward without the live smoketest and backlog it. The build is proven by offline tests against recorded responses, and the live confirmation is a backlog item. | Jordan asked "Can we move forward and backlog the smoketest?", 2026-10-07; reading that question as a yes is Claude's |
| D3 | `/upgrade` keeps an owner-edited bump file that upstream has not changed (`B != M`, `S == M` → `KEEP-LOCAL`), listed in the PR as "yours, nothing upstream" (OQ1 option a). | Jordan, 2026-10-07 |
| D4 | No prose fallback: when a gate script cannot run, `/sync` reports `not-checked (<reason>)` and skips that source (OQ2). | Jordan, 2026-10-07 |
| D5 | Ship Monday's widened fingerprint (P2) now, with offline tests, and `monday.md` §1 saying it is unconfirmed until a live run. Waives the live-proof bar for this release only. | Jordan, 2026-10-07 |
| D6 | The subscribed-path eval case uses a marker only `routing-smoke.sh` understands, and its description says it is smoke-runner-only (OQ3). | Jordan, 2026-10-07 |

**What D2 implies (Claude's reading, not a separate decision).** `CONTRIBUTING.md` ("proven live
against a real source before it's accepted") and `docs/proofs/README.md` set a live-proof bar for
adapter behaviour. P2 changes Monday's fingerprint, and P1 re-implements every gate, without that
proof. Backlogging the smoketest therefore waives the bar for this release. The mitigation is that
`monday.md` §1 says in so many words that the widened fingerprint is unconfirmed pending L1, and the
ROADMAP carries L1–L4 as open items. If Jordan did not mean to waive the bar, P2 waits for L1.

P1–P5 below are Claude's proposals; Jordan answered the open questions (D3–D6) and approved the
build on 2026-10-07 without reviewing P1–P5 line by line. Where a step said it depended on an open
question, use the matching decision.

## Proposed design

### P1. Gate scripts: one per built-in adapter *(proposed)*

`scaffold/.brainforge/gate-figma.sh`, `gate-github.sh`, `gate-website.sh`, `gate-monday.sh`,
`gate-ga.sh`.

- **Call:** `bash .brainforge/gate-<type>.sh [<source-id>…]`, run from the brain root. With ids
  it gates those entries; with none it gates every enabled entry of its type. `/sync <type> <id>`
  passes the id; `sync-all.md` and `/sync-health` call each type's gate once with no ids. This is
  what lets Monday keep one call for all its boards (golden rule 1). The script reads entries
  from `sources.json`, stored slots from `.sync-state.json`, and credentials from `.env`. It reads
  `.env` by matching `^KEY=` and never by sourcing the file, because sourcing executes it.
- **Read-only.** It never writes `.sync-state.json`. The state write stays in the adapter's §3,
  after the PR exists, as it does today.
- **Output contract:** one JSON object per gated entry, one per line on stdout (JSON Lines),
  exit 0:
  ```json
  {"type":"monday","id":"roadmap","status":"changed","reason":null,
   "fingerprint":{...},"stored":{...},"delta":[...]}
  ```
  `status` is one of `unchanged | changed | never | not-checked | blocked`.
  - `fingerprint` is in the shape §3 stores, so §3 copies it and does not rebuild it. The one
    exception is website, below.
  - `not-checked` takes `reason` from `/sync-health`'s existing vocabulary (`no clone`,
    `no credentials`, `offline`).
  - `blocked` means stop and ask the owner. It covers GitHub's remote mismatch, an unparseable
    `.brainforge-source.yml`, and a stored `lastSha` that is no longer in the fetched history
    (force-push or rebase).
  - `never` means extract regardless of the gate: no stored slot, or (figma) an entry whose
    `<into>` holds none of its output yet.
  - Exit 1 is only for misuse (an unknown id, or no `sources.json`), with a message on stderr.
  - A caller that gets no JSON treats the source as `not-checked (gate failed)`. It never treats
    it as unchanged.
- **Per adapter.** Each gate runs the §1 call the adapter already documents, with these
  additions:
  - *figma:* calls once per `fileKey` and emits one object per entry. When the call trips, every
    enabled entry sharing that key reports `changed` (the widening rule in §1). An entry whose
    `<into>` directory is missing or has no files reports `never`, whatever the shared slot says
    (`figma.md` §1, "extracts regardless of the gate"). The gate checks the filesystem for this so
    no caller has to remember it.
  - *github:* checks the clone's origin before fetching. It applies `.brainforge-source.yml`
    from the fetched ref using a strict parser for the documented subset (`version: 1`, then
    `never-summarize` / `summarize` lists of quoted globs, with `**` treated as a prefix match);
    anything else gets `blocked`. `delta` lists the in-scope paths plus an `excluded` count. It
    never lists excluded names.
  - *website:* keeps `website.md` §1 exactly as written, no change in behaviour. It fetches the
    sitemap. A URL whose `<lastmod>` differs from stored, or that is new, goes in `delta`. A URL
    whose `<lastmod>` equals stored gets a conditional `GET` with the stored validators
    (`If-None-Match: <etag>`, `If-Modified-Since: <lastmod>`); 304 skips it, anything else puts it
    in `delta`. A URL with no `<lastmod>` gets the same conditional `GET`. The stored validators
    come from the slot, `websites[<id>].urls[<url>] = {lastmod, etag}`.
    The fingerprint is that same per-URL map. For URLs that were skipped it carries the stored
    etag (or the one the 304 returned); for `delta` URLs it carries the new `<lastmod>` and
    `etag: null`, because the gate never fetched the page. §3 stores the fingerprint and then sets
    the etag for each URL §2 fetched from that fetch's response. That merge is the exception to
    "copy verbatim".
  - *ga:* runs the trailing-window `sessions`-by-`date` report. The window start is computed
    from the stored `lastSyncedThrough − lookbackDays`; the end is the literal string
    `"yesterday"`, passed to the API as `ga.md` §1 does, so "yesterday" is in the property's
    reporting time zone and the script never computes it from the local clock. `maxDate` is the
    newest date in the response rows. No stored slot → `never` with no call (the first run is
    a backfill anyway). Credentials, in order:
    1. `GOOGLE_APPLICATION_CREDENTIALS` set in `.env` → the script exports it, then runs
       `gcloud auth application-default print-access-token` (the documented unattended path);
    2. otherwise the same `gcloud` command against the owner's own-OAuth-client ADC;
    3. no `gcloud`, or the command fails → `not-checked (no credentials)`.

    Whether `print-access-token` honours an exported service-account key is unconfirmed; live
    check L3 covers it.
  - *monday:* see P2.
- **Offline tests:** a test-only `curl` stub goes first on `PATH`
  (`tests/lib/curl-stub.sh`). It matches the requested URL plus the POST body against
  `tests/fixtures/gates/<type>/*.http` and prints the recorded response or status. The shipped
  scripts carry no test-only branches. The GitHub gate is tested against a local bare repo used
  as `origin`. No test uses a credential, and none touches the network.

### P2. Monday's in-place-edit gap *(proposed)*

Widen the fingerprint to `(updated_at, items_count, lastActivityAt)` and get it from the same
single call:

```graphql
query ($ids:[ID!]) { boards (ids:$ids) { id updated_at items_count activity_logs (limit:1) { created_at } } }
```

`lastActivityAt` is the newest activity event's `created_at`, compared as an opaque string, or
`null` when retention has expired. If any of the three moves, the board is in the delta. The
widened fingerprint catches everything the current one does and more, at the cost of one nested
field. A stored slot with no `lastActivityAt` (every existing brain) reports `changed` once, so
each brain gets one extra sync after the upgrade. `monday.md` §1 says the widened fingerprint is
unconfirmed until live check L1 runs.

### P3. `envelope-check.sh` *(proposed)*

`bash .brainforge/envelope-check.sh <prev-manifest> <manifest> <sources.json> [source-id…]`

- It checks every doc and `_index.md` in the domain each named source writes to (its `into`).
  With no ids it checks all enabled sources. It checks the whole domain rather than only the docs
  emitted this run because a breach nobody accepted should keep showing, and the script cannot
  see which files this run emitted.
- It resolves envelopes in the order `sync.md` already gives:
  1. the matching `acceptedSize` entry;
  2. the row in the adapter's `0a. Size envelope` table;
  3. 8,000.

  Adapter lookup: the sources-key maps to the adapter file (`repos`→`github`,
  `websites`→`website`, any other key is its own name). The table is parsed with a fixed grammar,
  written to fit all five shipped tables as they are today:
  - first cell: a backticked filename (an exact row), a backticked `<placeholder>.md` or the
    words `per-page file` (a wildcard row), or `domain total` / `per-domain total` (the domain
    row). Bold wrapping (`**…**`) is stripped first. Any text after the closing backtick is
    ignored (`figma.md`'s `` `figma-library.md` (style + component-set inventory) ``);
  - second cell: `≤ N` with optional thousands commas, after stripping bold. A trailing word such
    as `each` is ignored;
  - an exact row beats a wildcard row, so in `monday.md` `_index.md` resolves to its own row and
    never to `<board>.md`.

  A table that does not parse prints
  `⚠ rule-6: <adapter> envelope table unreadable — used the 8,000 default` instead of silently
  defaulting.
- It prints exactly today's two line formats, one per breach:
  `⚠ rule-6: <path> is <N> tokens (envelope <M> / was <P>) — consider aggregating.` and
  `⚠ rule-6: <domain> totals <N> tokens (envelope <M>) — consider aggregating.`
  - `P` is `n/a` when there is no baseline: no prev file, a doc missing from it, or an
    `_index.md` whose prev manifest is older than schema 2.
  - The 3× growth check also applies to accepted docs.
  - With no domain-total row, the domain check is skipped.
  - No breach means no output, and exit 0. Bad arguments or an unreadable manifest exit 1 with a
    message.
- `sync.md` step 3 keeps `$PREV`. Its arithmetic paragraphs collapse to: run the script, then
  paste its lines into the PR body verbatim.

### P4. Session hooks move into `.brainforge/session-start.sh` *(proposed)*

- **The script:** `scaffold/.brainforge/session-start.sh` (bump) holds today's four hooks, in
  today's order and with today's behaviour.
  - Each hook runs in its own subshell, so one failure cannot silence the others.
  - The script always exits 0.
  - The whole body sits inside a `main` function, and the last line is `main "$@"; exit`. Bash
    reads a script as it runs, and hook 1 (`git pull`) can rewrite this very file mid-run. The
    function makes bash parse the body before anything executes, and the `exit` on the same line
    stops bash from reading on into whatever bytes a longer rewritten file has after that point.
  - The explanatory `$comment` that today sits in `settings.json` moves into the script's header
    comment, because it names `last-drift-review`, which is the legacy detector's signature.
- **Thin `settings.json`:** the shipped `scaffold/.claude/settings.json` becomes one
  `SessionStart` hook, keeping today's `"matcher": "startup|resume"`, and a short `$comment` that
  points at the script without naming `last-drift-review`:
  `[ -r "$CLAUDE_PROJECT_DIR/.brainforge/session-start.sh" ] && bash "$CLAUDE_PROJECT_DIR/.brainforge/session-start.sh" || true`.
- **Legacy detector:** the script greps `.claude/settings.json` for the old inline hook's
  signature (`last-drift-review`). On a hit it prints one line:
  `⚠️  .claude/settings.json still has the old inline session hooks — delete them; .brainforge/session-start.sh runs them now.`
  This catches the half-done migration in which an owner adds the new line but keeps the old
  hooks, which would print every nudge twice.
- **Migration for existing brains:**
  - *Stock `settings.json` (bytes match the baseline):* `/upgrade` makes it `OVERWRITE` and
    `ADD`s `session-start.sh`. Nothing to do by hand.
  - *Owner-edited `settings.json`:* it gets `FLAG-MODIFIED` once with an `UPSTREAM-CHANGED`
    delta, which is the four inline hooks swapped for one line. The owner applies that by hand
    and re-baselines. Until they do, the old inline hooks keep running. Nothing regresses, but
    those hooks no longer receive fixes. `/upgrade` §6's PR body gets a one-line instruction for
    this file.
  - *Later upgrades:* see Open question 1. Without that classifier change, the owner-edited file
    keeps flagging.
  - *Brains that skip versions* get the same treatment, because `settings.json` stays a bump
    path. The migration does not depend on landing on one particular release.
- **`.sync-state.json` comment.** Its `$comment` names `.claude/settings.json` as the tripwire's
  parser. In the scaffold copy, repoint it to `.brainforge/session-start.sh`. That file is `once`,
  so existing brains keep the stale pointer. That is harmless, and changing it is not worth a
  hand-edit item.

### P5. Routing evals *(proposed)*

- **Fixture domains** for the four intents with nowhere to route:
  - `context/derived/analytics/` with `kinds: [analytics, metric-definitions]`
  - `context/derived/repos/` with `kinds: [repo-summaries, eng-conventions]`
  - `context/derived/web/` with `kinds: [site-inventory, product-catalog]`
  - `context/canon/audience/` with `kinds: [user-archetypes, positioning]` (canon, because
    archetypes and positioning are owned by a human, not synced)

  Each gets one `_index.md` and one doc carrying a fact the model could not guess. The other two
  uncovered intents already have a domain: naming through `canon/brand` (`naming`), and
  design/art-direction through `canon/design` (`design-principles`). Regenerate the fixture
  manifest afterwards.
- **One case per uncovered intent:** `naming-question`, `design-decision`, `metrics-question`,
  `eng-conventions`, `catalog-question`, `audience-question`. Each has a `tool_used` grader on the
  domain's doc and a `regex` grader on the fact. The existing cases use the same pattern. With
  these, all 13 intents have a case.
- **Subscribed-path case `stranded-file-subscribed`:** the same prompt and graders as
  `stranded-file`, but the cwd is empty and the brain is reachable only by subscription.
  - The case dir carries a `subscribe` marker file.
  - `routing-smoke.sh` sees the marker and turns the fixture into a git repo in `$TMP`.
  - It runs `claude -p` with `SYNAPSE_HOME=$TMP/synapse-home` and `SYNAPSE_BRAINS=<that repo>`,
    plus `--add-dir $SYNAPSE_HOME`, because `--restricted` confines reads to the add-dirs.
  - The real hook clones the repo and renders the map the reader gets.
  - **Unverified:** whether plugin `SessionStart` hooks fire under `-p --restricted`. If they do
    not, the runner runs `synapse/hooks/session-start.sh` itself and passes its output with
    `--append-system-prompt`. Plan step 11 settles this with a probe.
- **README rule** (`synapse/routing/README.md`): every `intents.json` change must come with a
  passing `bash synapse/evals/routing-smoke.sh` run. `claude plugin eval` is the stronger check
  when available, not the requirement. The claim still has to say which runner was used.

## Live checks (backlogged, D2)

These can only be confirmed against real sources. Each one gets a proof file in `docs/proofs/`
when it runs.

- **L1 Monday:**
  - (a) Does a pure in-place column edit bump the board's `updated_at`?
  - (b) Does `activity_logs(limit:1)` return the *newest* event, and does that edit produce one?
  - (c) What does `created_at` look like, and is it stable when nothing changes?
  - (d) Is the query's complexity cost acceptable for the allowlisted boards?
  - (e) Does an immediate re-run report `unchanged` (golden rule 1)?

  If (b) fails, the fallback is `activity_logs(from: <lastSync>, limit:1)`, where non-empty means
  changed.
- **L2 every gate:** one live run per built-in returns `unchanged` on an unchanged source, and
  the JSON fingerprint equals what §3 stored. That is golden rule 1, re-proven through the
  script.
- **L3 GA:** `gcloud auth application-default print-access-token` returns a token that
  `runReport` accepts, on both paths: the own-OAuth-client ADC, and a service-account key exported
  as `GOOGLE_APPLICATION_CREDENTIALS`. If the second fails, the gate swaps step 1 for a path that
  does work and `ga.md` says which.
- **L4 session hooks:** a real Claude Code session in an upgraded brain prints the same nudges as
  before, and the legacy detector fires on a brain whose `settings.json` holds both the old and
  new hooks.

## Open questions

1. **Stop re-flagging owner-edited bump files when nothing changed upstream?** As the finding
   above shows, the script move by itself does not deliver item 4's claim. Options:
   - **(a)** Add a classifier row: `B != M` and `S == M` → `KEEP-LOCAL`. This keeps the baseline,
     writes nothing to disk, and lists the file in the PR body as "yours, nothing upstream". It is
     still pure byte/set logic.
   - **(b)** Move `.claude/settings.json` to `runtime.once`. That stops the flags, but no
     existing brain then receives the thin file. Owners of stock files would also have to
     hand-edit, and `settings.json` could never be updated again.
   - **(c)** Accept the flags.

   **Recommend (a).** It is a handful of lines in `upgrade.md`'s python fence, and it fixes the
   same false alarm for every bump file, not only this one. Resolved: (a), D3.
2. **When a gate script cannot run (no `gcloud`, no clone), may `/sync` fall back to running the
   gate from the adapter's prose?** **Recommend no.** Report
   `not-checked (<reason>)` and skip that source. A prose fallback brings back the unverifiable
   path this work removes, and the cadence verdict already handles `not checked`. The cost: a
   machine without `gcloud` can no longer sync GA until it is installed. Resolved: no fallback, D4.
3. **Should the subscribed case rely on a marker that only `routing-smoke.sh` understands?**
   `claude plugin eval` would run it as an empty-cwd case and fail it. Options:
   - a runner-only marker;
   - a `context.env` field in `case.yaml`, which may or may not be valid for the real harness;
   - wait for harness support.

   **Recommend the marker**, with the case's description saying it is smoke-runner-only. Since
   the README now names `routing-smoke.sh` as the required runner, this case counts. Resolved: the marker, D6.

## Plan

Branch from `main`. Steps 1–7 cover gates and envelopes, 8–9 hooks, 10–12 evals, and 13 the
release. Step 7 follows D4, Step 9 follows D3, and Step 11 follows D6.

Every gate test runs offline and deterministically: it builds `$TMP/bin/`, puts the stubs there
under the names the gates call (`curl`, and for GA `gcloud`), and runs the gate with
`PATH="$TMP/bin:/usr/bin:/bin"`, so no real `curl` or `gcloud` on the machine is ever reached.

### Step 1 — gate test harness (mechanical → implementer)

Files: `tests/lib/curl-stub.sh`, `tests/fixtures/gates/README.md`, `tests/gate-harness.test.sh`
Change: The stub is a plain script; each test links it into place as `$TMP/bin/curl` and puts
`$TMP/bin` first on PATH. It parses `-X`, `-d`/`--data`, `-H`, `-o`, `-w '%{http_code}'`
and the URL. It scans `$CURL_STUB_DIR/*.http` for the first file whose first line,
`# match: <METHOD> <URL-regex> [<body-regex>]`, matches the request. It prints the body, and when `-w`
asks for it, the recorded status. With no match it exits 7, which is curl's "couldn't connect"
code, so a missing fixture looks like offline and never like success. It also logs every call to
`$CURL_STUB_DIR/calls.log` so tests can count heavy calls.
Verify: `bash tests/gate-harness.test.sh` (a new, small self-test that shows match, no-match → 7,
and the call log) → `PASS gate-harness`.

### Step 2 — `gate-github.sh` (judgment)

Files: `scaffold/.brainforge/gate-github.sh`, `tests/gate-github.test.sh`
Change: P1 contract. Steps in order:
1. Look up the entry by id under `repos`.
2. `localClone` missing → `not-checked (no clone)`.
3. Origin mismatch, comparing host/org/repo and ignoring scheme and `.git` → `blocked`.
4. `git fetch --quiet`; failure → `not-checked (offline)`.
5. No stored `lastSha` → `never`.
6. `git cat-file -e <lastSha>^{commit}` fails, or `lastSha` is not an ancestor of
   `origin/<branch>` → `blocked`, reason `lastSha not in fetched history`.
7. `git diff <lastSha>..origin/<branch> --name-only`.
8. Apply `.brainforge-source.yml` from `git show origin/<branch>:…`.
9. Print `fingerprint {lastSha: <origin HEAD>}`, the in-scope `delta`, and the `excluded` count.

Tests, against a local bare origin:
- (a) unchanged → `unchanged`, empty delta;
- (b) one in-scope commit → `changed`, delta = [that path];
- (c) a change only under `calls/` with `never-summarize: ["calls/**"]` → `unchanged`,
  `excluded: 1`, and the stdout never contains `calls/`;
- (d) a malformed yml → `blocked`;
- (e) a `remote` mismatch → `blocked`;
- (f) no slot → `never`;
- (g) the working tree is dirty and behind, but the result comes from the fetched ref;
- (h) origin force-pushed so the stored `lastSha` is gone → `blocked`;
- (i) two ids on one call → two JSON lines, one per entry.

Verify: `bash tests/gate-github.test.sh` → `PASS gate-github`. Mutation check: delete the
exclusion filter, and (c) must fail.

### Step 3 — `gate-figma.sh`, `gate-website.sh` (mechanical → implementer, one brief each)

Files: those two scripts, `tests/gate-figma.test.sh`, `tests/gate-website.test.sh`, fixtures
under `tests/fixtures/gates/{figma,website}/`
Change: P1 contract, each running its adapter's §1 call as written. Figma: `FIGMA_TOKEN` from
`.env`, `GET /v1/files/<fileKey>?depth=1` once per key, `fingerprint {version, lastModified}`,
one object per entry, and the empty-`<into>` → `never` rule. Website: no credentials, the §1
behaviour and the per-URL `{lastmod, etag}` fingerprint exactly as P1 describes.
Tests (recorded responses): unchanged; changed; no token → `not-checked (no credentials)`; stub
exit 7 → `not-checked (offline)`; HTTP 403 → `not-checked` with a reason that names the status;
no slot → `never`. Figma also: two entries sharing one fileKey make one call and both report
`changed`; an entry with an empty `<into>` on an unchanged key reports `never` while its sibling
reports `unchanged`. Website also: a URL with matching `<lastmod>` whose conditional GET returns
200 lands in `delta`; a changed URL's fingerprint carries `etag: null`; the conditional GET sends
the stored etag (assert from `calls.log`). Call-count assertions (golden rule 1): an unchanged
figma source logs exactly one call; an unchanged website source logs exactly one sitemap fetch and
every other logged call is a conditional GET answered 304.
Verify: both tests print PASS.

### Step 4 — `gate-monday.sh` (judgment)

Files: `scaffold/.brainforge/gate-monday.sh`, `tests/gate-monday.test.sh`, fixtures
Change: P2 query and fingerprint, with `MONDAY_API_TOKEN` from `.env`. The gate puts the
`boardId` of every entry it was asked to gate (all enabled monday entries when called with no
ids) into one request, and emits one object per entry. That keeps `monday.md` §1's "one GraphQL
call covering every allowlisted board". Treat a GraphQL `errors` array as `not-checked` with the
first message, for every entry in the call.
Tests: all three fields match → `unchanged`; only `lastActivityAt` moved (the in-place-edit case)
→ `changed`; a stored slot without `lastActivityAt` → `changed`; empty `activity_logs` →
`lastActivityAt: null` and no crash; a GraphQL error → `not-checked`; three entries with no ids
→ exactly one logged call and three JSON lines.
Verify: `bash tests/gate-monday.test.sh` → PASS. Mutation check: drop `lastActivityAt` from the
comparison, and the in-place-edit test must fail.

### Step 5 — `gate-ga.sh` (judgment)

Files: `scaffold/.brainforge/gate-ga.sh`, `tests/gate-ga.test.sh`, fixtures
Change: P1 contract and the `ga.md` §1 window: start date from the stored
`lastSyncedThrough − lookbackDays`, end date the literal `"yesterday"`. The script never reads
the local clock. Credentials in P1's order. Fingerprint `{lastSyncedThrough: maxDate,
trailingSessionHashes}`, with `maxDate` from the response rows. `delta` is the dates whose
sessions differ, plus any new date.
Tests, with a `gcloud` stub in `$TMP/bin` that prints a fake token and logs whether
`GOOGLE_APPLICATION_CREDENTIALS` was set in its environment:
- no new date and equal sessions → `unchanged`;
- a late-arriving revision to one day → `changed`, delta = that date;
- a new day → `changed`;
- the request body's `endDate` is exactly `"yesterday"` (assert from `calls.log`);
- `GOOGLE_APPLICATION_CREDENTIALS` in `.env` → the stub saw it exported;
- no `gcloud` in `$TMP/bin` (PATH holds no other) → `not-checked (no credentials)`;
- no stored slot → `never` and zero logged calls.
Verify: `bash tests/gate-ga.test.sh` → PASS.

### Step 6 — `envelope-check.sh` (judgment)

Files: `scaffold/.brainforge/envelope-check.sh`, `tests/envelope-check.test.sh`
Change: P3.
Tests, on hand-built manifests plus a scaffold-shaped `pipeline/adapters/` copy:
- (a) a doc over its adapter row → the per-doc line, exact bytes;
- (b) under the envelope but ≥3× prev → the line with `was <P>`;
- (c) an `acceptedSize` that covers it → silent; the same doc tripled → the line;
- (d) `_index.md` checked via `indexTokens`, with a schema-1 prev → `was n/a`;
- (e) the domain total is over while every doc is under → the domain line;
- (f) no adapter row → the 8,000 default;
- (g) a garbled table → the "unreadable" line;
- (h) a missing prev file → envelope-only;
- (i) clean → empty stdout, exit 0.

Also assert that every shipped `scaffold/pipeline/adapters/*.md` table parses with zero
"unreadable" lines. This catches a future adapter edit that breaks the grammar.
Verify: `bash tests/envelope-check.test.sh` → `PASS envelope-check`.

### Step 7 — wire gates and envelope into the commands (judgment, prose)

Files: `scaffold/.claude/commands/sync.md`, `scaffold/pipeline/sync-all.md`,
`scaffold/pipeline/sync-health.md`, `scaffold/pipeline/adapters/{figma,github,website,monday,ga}.md`
§1 and §3, `scaffold/pipeline/ADAPTER-TEMPLATE.md` §1, `scaffold/.brainforge/README.md`
Change:
- `sync.md`, `sync-all.md` and `sync-health.md` run `bash .brainforge/gate-<type>.sh <id>` and
  route on `status`, with no prose fallback (pending OQ2).
- `sync-health.md`'s upstream column reads `delta` length (`excluded` never named), and its
  verdict table maps `never` → ❌ and `blocked` → ⚠️ with the reason.
- Each adapter's §1 keeps its explanation and gains "the gate is `.brainforge/gate-<type>.sh`;
  this section documents what it does". §3 says to store the gate's `fingerprint` verbatim.
- `monday.md` §1 describes the P2 fingerprint as unconfirmed pending L1.
- `sync.md` step 3's arithmetic is replaced by the P3 call, keeping `$PREV`.
- `ADAPTER-TEMPLATE.md` §1 says a custom adapter may ship a gate script with the same contract.
- The README documents the JSON contract.

- `website.md` §3 states the etag merge from P1.
- `sync-all.md` and `sync-health.md` call each type's gate once with no ids; `sync.md` passes
  the id.

Verify: `bash tests/sync-rules.test.sh && bash tests/sync-contract.test.sh` → PASS, with the
assertions changed where they quote moved prose. These only show nothing regressed; they do not
test the new wiring. The wiring evidence is the next two checks.
`grep -n "gate-" scaffold/.claude/commands/sync.md scaffold/.claude/commands/sync-health.md scaffold/pipeline/sync-all.md scaffold/pipeline/sync-health.md`
must show a call in all four, and
`grep -c "rule-6" scaffold/.claude/commands/sync.md` must show only the call and its relay
instruction. Get those counts from running the commands, never from the prose.

### Step 8 — `session-start.sh` and thin `settings.json` (judgment)

Files: `scaffold/.brainforge/session-start.sh`, `scaffold/.claude/settings.json`,
`tests/sync-tripwire.test.sh`, `tests/canon-health.test.sh`, `tests/org-name-safety.test.sh`,
`tests/session-start.test.sh` (new), `scaffold/.brainforge/README.md`, `scaffold/.sync-state.json`
(`$comment` only)
Change:
- P4. Move the four commands over verbatim. Each one reads `$CLAUDE_PROJECT_DIR` and falls back
  to the script's own `../`.
- Repoint the existing tests at the script. `sync-tripwire` and `canon-health` invoke
  `bash session-start.sh` against their fixture brains and assert the same outputs.
  `org-name-safety` checks that the thin `settings.json` and the script stay valid for the hostile
  org names. Its `[ "$n" -ge 3 ]` assertion (line 26) becomes `[ "$n" -eq 1 ]`, and it adds
  `bash -n .brainforge/session-start.sh` for each org, so the valid-shell check now covers the
  script body. Do not weaken it to `-ge 1`.
- The new test checks:
  - (a) all four nudges fire on a brain that trips each one;
  - (b) a brain that trips none prints only the pull line;
  - (c) one hook made to fail (an unreadable `.sync-state.json`) does not suppress the others;
  - (d) the legacy detector fires when `settings.json` contains `last-drift-review` and stays
    silent on the shipped thin file, `$comment` included;
  - (e) the script rewritten mid-run by a fake `git pull` still completes. Do this by putting a
    stub `git` on PATH that overwrites the script.

  - (f) the thin `settings.json` keeps `"matcher": "startup|resume"`.

Verify: those four tests print PASS. Mutation check: remove the `main` wrapper or the trailing
`; exit`, and (e) must fail. Make (e)'s fake `git pull` write a longer file with a marker line
after the original length, so the failure is deterministic rather than timing-dependent. Pad
the test's copy of the script with a comment block bigger than bash's read buffer after hook 1,
and have the fake pull replace everything after the padding with marker lines. Without that,
the whole script fits in one read and a missing wrapper still passes.

### Step 9 — `/upgrade` handling (judgment; first half contingent on OQ1)

Files: `commands/upgrade.md`, `tests/upgrade-rebaseline.test.sh` (or a new
`tests/upgrade-keep-local.test.sh`)
Change:
- If OQ1 resolves to (a), add `KEEP-LOCAL` to the action table and to the steady-state branch.
  Condition: `inS and inB and inM and B[f] != M[f] and S[f] == M[f]` → `acts[f]="KEEP-LOCAL"`,
  `newman[f]=M[f]`. Then list `KEEP-LOCAL` in the PR body as "yours, nothing upstream to bring
  in". This must stay inside the only ```python fence, because `forge.md` extracts it.
- In every case, the §6 PR body gets the `settings.json` migration line from P4.

Tests, on a fixture brain:
- an owner-edited `settings.json` and a changed shipped file → `FLAG-MODIFIED`;
- after re-baselining, the same owner file and an unchanged shipped file → `KEEP-LOCAL`, nothing
  written;
- a stock file → `OVERWRITE`;
- a same-version re-run reports `UP-TO-DATE`, with no `UNBUMPED-CHANGE` caused by the kept
  baseline.

Verify: the test prints PASS. `bash tests/upgrade-*.test.sh && bash tests/fence-contract.test.sh`
→ all PASS.

### Step 10 — fixture domains for uncovered intents (mechanical → implementer)

Files: `evals/fixtures/acme-brain/context/derived/{analytics,repos,web}/{_index.md,<doc>.md}`,
`evals/fixtures/acme-brain/context/canon/audience/{_index.md,<doc>.md}`,
`evals/fixtures/acme-brain/.brainforge/brain-manifest.json`
Change: P5 domains. Each doc holds one unguessable fact (a number, a date, a named convention).
Regenerate the manifest with `scaffold/.brainforge/gen-manifest.sh` the way
`fixture-manifest.test.sh` does, and commit it.
Verify: `bash tests/fixture-manifest.test.sh && bash tests/routing-coverage.test.sh` → PASS. On
the regenerated manifest, `bash synapse/routing/coverage.sh <manifest>` reports no unroutable
kind.

### Step 11 — eval cases, the subscribed-path runner and a probe (judgment)

Files: `synapse/evals/routing/{naming-question,design-decision,metrics-question,eng-conventions,catalog-question,audience-question,stranded-file-subscribed}/`,
`synapse/evals/routing-smoke.sh`, `synapse/evals/routing/stranded-file/case.yaml` (the NOTE now
points at the new case)
Change:
- First, the probe: one `claude -p --restricted --plugin-dir synapse` run with `SYNAPSE_BRAINS`
  set to a local fixture repo. Record in the runner's header comment whether the `🧠` map appears
  in the stream-json. Then build the P5 runner branch that fits the result.
- The six intent cases use the existing scaffold.sh shape.
- The subscribed case has no `scaffold.sh` and does have a `subscribe` marker.

Verify: `bash synapse/evals/routing-smoke.sh` on each new case name → PASS. This is a paid local
run at about $0.25 per case, not part of CI, so record the output in the PR. Also confirm in the
subscribed run's jsonl that no Read touched a cwd manifest.

### Step 12 — README eval rule (judgment, prose)

Files: `synapse/routing/README.md`
Change: P5 README rule. Replace the "MUST come with a passing `claude plugin eval`" paragraph and
the fallback paragraph with one rule that names `routing-smoke.sh` as required and the harness as
stronger when available.
Verify: read by eye. `grep -n "routing-smoke.sh" synapse/routing/README.md` shows it in the rule
sentence.

### Step 13 — seam, versions, CHANGELOG-equivalent (mechanical → implementer)

Files: `.claude-plugin/plugin.json`, `synapse/.claude-plugin/plugin.json`, `ROADMAP.md`
Change:
- In `runtime.bump`, add `.brainforge/gate-figma.sh`, `gate-github.sh`, `gate-website.sh`,
  `gate-monday.sh`, `gate-ga.sh`, `envelope-check.sh` and `session-start.sh`.
- `version` 0.14.1 → 0.15.0, and synapse 0.7.4 → 0.7.5 (runner and README).
- ROADMAP gets a "Phase D: executable sync checks" section after **Field hardening**, naming
  the critique it answers and linking this spec, plus the backlogged live checks L1–L4 as
  unchecked items.

Verify:
- `python3 -c 'import json;b=json.load(open(".claude-plugin/plugin.json"))["runtime"]["bump"];print(sum(p.startswith(".brainforge/gate-") or p in (".brainforge/envelope-check.sh",".brainforge/session-start.sh") for p in b))'`
  → `7`.
- An `/upgrade` dry run of this branch (the python fence extracted per `commands/forge.md`)
  against a fixture brain born from the 0.14.1 scaffold reports `ADD` for the seven scripts and
  `OVERWRITE` for `.claude/settings.json`.
- `for t in tests/*.test.sh; do bash "$t" || echo FAIL $t; done` → no FAIL.

## What diverged

- `gate-website.sh` converts the stored `<lastmod>` to an HTTP-date for `If-Modified-Since`, and sends none when it does not parse. P1 said website keeps §1 unchanged; a raw W3C date is a value servers must ignore (RFC 7232 §3.3), so ETag-less sites would read `changed` every run. `website.md` §1 documents the conversion.
- `gate-figma.sh` called with ids also gates every enabled sibling that shares the fileKey, since one file fetch answers for all of them.
- `gate-github.sh` sets `GIT_TERMINAL_PROMPT=0` and adds `-oBatchMode=yes` to `GIT_SSH_COMMAND`, so a fetch that wants credentials fails fast as `not-checked (offline)` instead of hanging.
- `gate-github.sh`'s scope-file parser first treated a trailing `# comment` on a key line as the value, which blocked the example printed in `github.md` §0b. Fixed; test (c0) now parses that example straight from the doc.

The build follows the Plan except in these places.

- **GitHub gate order.** `gate-github.sh` parses `.brainforge-source.yml` before the `never`
  check (Step 2 put `never` at 5 and the yml at 8). A never-synced repo with a malformed yml is
  now `blocked` instead of handed to extraction, which would otherwise read the repo with no
  scope rules at all. Test (d) asserts this order on purpose.
- **Figma `blocked`.** `gate-figma.sh` reports `blocked` for an entry with no `into:`. P1
  reserved `blocked` for GitHub's three cases, but without `into:` the gate cannot do its
  `never` check, and the entry cannot be extracted anywhere, so stopping to ask the owner is
  the only safe answer.
- **`/sync --full`.** The spec was silent on it. `sync.md` now runs the gates as usual, then
  extracts everything for every `unchanged`, `changed` and `never` entry, ignoring `delta`.
  `blocked` and `not-checked` entries still skip, so `--full` cannot bypass a remote mismatch,
  a missing credential or a force-push.
- **`not-checked` reasons.** Beyond P1's three (`no clone`, `no credentials`, `offline`), the
  gates also report `HTTP <code>`, `GraphQL error: <message>`, `board not in response` and
  `unparseable response`. Step 3 asked for specific reasons; P1's vocabulary was not updated to
  match. Every one of them still reads as "not checked", never as unchanged.
- **Step 11 probe.** Plugin SessionStart hooks do fire under `claude -p --restricted`
  (recorded in the header of `synapse/evals/routing-smoke.sh`), so the runner relies on the real
  hook and no `--append-system-prompt` branch was built.

## Review notes

Critic review of the first draft, 2026-10-07. Every finding was accepted; none rejected. Two were
resolved in a way worth noting:

- **Status.** Set to `spec` rather than resolving OQ1–3, because only Jordan can answer them.
- **D2 vs the live-proof bar.** Stated as Claude's reading of D2 with a way out (P2 waits for
  L1), not added as a fourth open question, to keep the list at three.

## Verification

`bash synapse/evals/routing-smoke.sh <case>`, 2026-10-07, one run each, every grader passing:
naming-question ($0.16, 12 turns), design-decision ($0.14, 9), metrics-question ($0.12, 9),
eng-conventions ($0.12, 9), catalog-question ($0.14, 11), audience-question ($0.12, 9),
stranded-file-subscribed ($0.13, 8). The subscribed run passed the runner's check that the
SessionStart hook's map appeared in the stream. All 27 `tests/*.test.sh` pass.
