# Backlog remediation

Status: built
Reviewed: 2026-09-11 (third pass) — needs revision (four small Plan fixes, applied the same day; design settled)
Date: 2026-09-11

Written when this repo had a private dev twin and a /publish step; both are retired (see 2026-10-07-one-repo.md). File names like ROADMAP.public.md refer to that era. D11 (no em dashes) is retired too. Commit shas cited here predate the repo merge and no longer resolve.

## Goal

Clear the open issue backlog. On 2026-09-11 there were 17 open issues: 4 in a private
tracker and 13 on the public `jrpease/brainforge` tracker. Once this ships, every one is either
fixed and closed with a link to its fix, or closed with a stated reason. The fixes ship as a
single brainforge release (D14).

## Non-goals

- The roadmap's deferred items that issues point at. These need field evidence, not code:
  federation parts 2 and 3 (pub #21), regenerating the manifest in CI after merge (pub #16), the
  narrow-gate marker in the map (pub #17), and a source-side sync trigger (pub #20).
- Adding CI to either repo. Neither has `.github/`. New tests only run when someone runs them.
- Applying source-declared scope (pub #19) to non-repo adapters.
- Any change to `synapse/routing/intents.json`.
- A lint that fails when a bump path changes without a version bump (D7). If it is wanted later,
  it gets its own spec.
- Putting the org name back into brain hook messages (D4).
- Extracting the duplicated `fm()` helper into a shared file (D10).
- Rewriting paths like `adapters/github.md` inside `scaffold/pipeline/`. That issue is about `../`
  paths only; those other forms resolve from `pipeline/` and are left as they are.

## Decisions

All rows except D1 were settled on 2026-09-11, when the user accepted the recommendation for each
open question and for the three choices the second review found the spec making silently.

| # | Decision | Chose | Why | Rules out |
|---|---|---|---|---|
| D1 | Scope | Fix the outstanding backlog | The request on 2026-09-11 | Leaving triaged issues open with no action |
| D3 | pub #26: how to tell that one source never synced | A per-source `"synced": false` flag inside the source's slot in `.sync-state.json`, set by `/add-source` and flipped by each adapter. The tripwire keeps its `lastFullSync: null` check as a fallback | Fixes new sources in every brain without editing a `once` path; brains without the flag behave as today | Caveat only; migrating existing `.sync-state.json` files |
| D4 | pub #29: org name in hook messages | Close as by design | F1 removed `{{ORG}}` from hook strings because names like `Levi's` broke them. The hooks only run inside the brain's own repo, and subscribers already see the brain named by the synapse hook | A run-time org-name lookup in the hooks |
| D5 | Validating JSON in a dependency-free script | Fix escaping at the source. Then validate with `python3` when it is installed and skip when it is not; exit non-zero when validation fails. Tests validate unconditionally | Correct escaping is the fix and the check is a backstop, so the script's git/find/sed/awk/wc promise holds | A hand-written awk JSON checker; a hard `python3` dependency |
| D6 | `_index.md` size limits | Enforce them from the manifest's `indexTokens` | The number already exists (schema 2), and six adapters declare limits | Dropping the `_index.md` rows from the adapters |
| D7 | pub #25: lint for unbumped bump-path changes | No | Step 3 covers the user-facing harm; there are no git tags to diff against | The lint, in this spec |
| D9 | Eval spend | Approved: about 6 runs of `routing-smoke.sh` at about $0.22 each | Two issues (pub #18, #28) cannot close without a run | Closing them unverified |
| D10 | Duplicated `fm()` in `canon-health.sh` and `gen-manifest.sh` | Keep the duplicate | A shared `lib.sh` adds a bump file and a new failure mode (missing or stale `lib.sh`) to scripts meant to run standalone | A shared `.brainforge/lib.sh` |
| D11 | No em dashes in the five public docs | A standing repo rule: enforced by `tests/public-docs.test.sh` and stated in `CONTRIBUTING.md` | It was a Global Constraint of the v0.6.0 plan, and without a test it already broke once (`ROADMAP.public.md:177`) | Leaving it undocumented; dropping it |
| D13 | Release versions | brainforge `0.10.0` → `0.11.0`. synapse `0.7.1` → `0.7.2` only if a synapse behavior file (such as `SKILL.md`) changes | Minor matches every brainforge release from 0.3.0 to 0.10.0 except 0.9.1 | `0.10.1`; a synapse minor bump for a wording change |
| D14 | Release shape | One release | Only two step groups touched the same files; strict serial merging would wait for no reason | A release per step group; strictly serial merging |
| D15 | pub #25: how `/upgrade` detects unbumped changes | Compare shipped bump-file hashes against the manifest baseline | `emitted-from` can be empty (a plugin-cache checkout is not a git repo) or name a commit in the other repo | The issue's suggested `git diff <emitted-from>` |
| D16 | The `_index.md` limits issue's "done when" asks for a test that fails on today's `sync.md` | A shallow text test, `tests/sync-rules.test.sh`, asserting the three old caveat sentences are gone | There is no harness for command prose; a text test is honest about what it proves and does fail on today's `main` | Review by eye only |

## Constraints

These are facts about the repos, not choices. Every step must respect them.

- **`commands/upgrade.md` has exactly one ```python fence.** `commands/forge.md` §3 extracts it
  with `awk '/^```python$/,/^```$/'`, a range that joins every python fence in the file. A second
  fence silently breaks fresh installs. New ref-scan logic (Step 4) must be bash.
- **`gen-manifest.sh` output formatting is a parsing contract.** It uses 2-space indent, one key
  per line and single-line file entries. The synapse hook reads it with grep, sed and awk.
- **Never auto-edit a `once` path** in an existing brain. `.sync-state.json`, `sources.json` and
  `README.md` are `once` paths. Changing the scaffold copy only affects new brains.
- **Bump `.claude-plugin/plugin.json` once, in the release step.** Touching a `runtime.bump` path
  without a bump is invisible to `/upgrade`. Bump synapse only if something under `synapse/`
  changes behavior; `synapse/evals/**` and READMEs do not count.
- **Baseline:** all 9 scripts in `tests/` pass on `main` at `36a1999` (run 2026-09-11).

## Backlog triage (2026-09-11)

Each issue was checked against the code on `main` by an exploration pass, and the key anchors
were spot-checked by hand. Severity: high means broken output, medium means wrong docs or a
missing check, low means cosmetic.

### Private tracker

| Issue | Status | Sev | Step |
|---|---|---|---|
| `gen-manifest.sh` validates nothing | Still valid. A backslash in `kinds` gives invalid JSON; `brain`/`remote` are printed raw; the script always exits 0 | high | 6 |
| Shopify example and sync-all missed F3/F6/F9 | Partly fixed (F9 done). `ADAPTER-TEMPLATE.md:82-85` has the same F3 gap | medium | 8 |
| `sync-health.md` uses a `../` path | Still valid. The same `../` form is at `ADAPTER-TEMPLATE.md:8,21,120` and `examples/shopify.md:5` | low | 2 |
| `sync.md` says `_index.md` has no token count | Partly fixed (domain total checked). The per-`_index.md` check is missing, 6 adapters declare limits nothing enforces | medium | 9 |

### Public tracker

| # | Issue | Status | Sev | Step |
|---|---|---|---|---|
| 16 | Staleness warning never clears | Already fixed (b396a20, 515eef0), shipped in v0.9.0 | n/a | closed |
| 17 | Doc reachability check | Already fixed (b396a20) | n/a | closed |
| 18 | unit-context intent | Fixed in code (`intents.json:12`); required eval run never done | low | 11 |
| 19 | Source-declared scope | Already fixed (`pipeline/adapters/github.md` §0a-bis, §0b) | n/a | closed |
| 20 | sync-health measures the calendar | Already fixed | n/a | closed |
| 21 | Federation / configurable context root | Part 1 shipped; parts 2 and 3 deferred | low | closed |
| 24 | Contract comments say FIRST, should say ONLY | Still valid. Latent: only one fence today | medium | 1 |
| 25 | `/upgrade` misses changes shipped without a version bump | Still valid (`upgrade.md:106` exits before hashing) | medium | 3 |
| 26 | `lastFullSync` is one global date | Still valid | medium | 7 |
| 27 | Eval fixture manifest out of date | Still valid (schema 2 header; token counts still correct) | low | 5 |
| 28 | Two routing eval failures | Still valid, not diagnosed | medium | 10 |
| 29 | Org name gone from hook messages | Removed on purpose in F1 (6c796c2); the issue's reasoning does not hold | low | closed (D4) |
| 30 | Ref-scan ignores § references | Still valid (`upgrade.md:215-227` matches paths only) | medium | 4 |

## Open questions

None. Every question raised by the first draft and both reviews was answered on 2026-09-11; see
Decisions.

## Cleanup pass findings (2026-09-11)

A read-through of the repo found the items below. Severity uses the triage scale above. Files the Plan already touches were read but not edited, and
nothing turned up in them that a Plan step does not already cover.

| Finding | Where | Sev | Disposition |
|---|---|---|---|
| An em dash in a public doc, against the no-em-dash rule (D11) | `ROADMAP.public.md:177` | low | **Applied**: the dash became a colon. Docs-only, no bump. |
| Nothing enforces the no-em-dash rule, which is how the one above got in | `tests/` | medium | **Applied**: new `tests/public-docs.test.sh` greps the five `publish.map` sources for U+2014. Passes clean; fails, naming the line, when one is injected into a copy. The release Verify loop runs it. |
| The private README pins `v0.5.0` and `synapse v0.2.0`; the manifests say `0.10.0` and `0.7.1` | `README.md:70-71` | medium | **Applied**: the sentence no longer states numbers and points at the two `plugin.json` files, so the release bump cannot re-stale it.  |
| The public roadmap names `/walk` three times and never mentions `/forge`. The private `ROADMAP.md:189` records the rename and keeps old names in history on purpose; the public copy has no such entry | `ROADMAP.public.md:35,39,43` | low | **Applied**: "since renamed `/forge`" on the first mention only, bullet rewrapped to width, history otherwise untouched. Docs-only, no bump. |
| `unowned=""` is set and never read | `scaffold/.brainforge/canon-health.sh:67` | low | **Applied**: removed. Bump path, so it rides the release bump. `tests/canon-health.test.sh` passes. |
| No `__pycache__/` ignore in a repo that ships a `.py` script; compiling or importing the scorer leaves untracked junk, and one appeared during this pass | `.gitignore` | low | **Applied**: added `__pycache__/`. The root `.gitignore` matches no include glob. |
| The `fm()` frontmatter helper is byte-identical in two shipped scripts | `scaffold/.brainforge/canon-health.sh:58-64`, `scaffold/.brainforge/gen-manifest.sh:95-100` | low | **Decided: keep** (D10). No step. |
| The rule the new em dash test enforces is stated nowhere a contributor reads | `CONTRIBUTING.md` | low | **Decided: document** (D11). Step 11b. |

Checked and left alone: the nine byte-identical `synapse/evals/routing/*/scaffold.sh` (their
header says why: `scaffold_script` is sandboxed to the case directory); `set -u` without
`pipefail` in `session-start.sh`, `coverage.sh` and `canon-health.sh` (fail-safe by design, per
the `settings.json` `$comment`); the `../` hrefs in `scaffold/context/*/README.md` and
`scaffold/.claude/commands/forge.md:6` (real markdown links GitHub resolves, and the
`upgrade.md:220` ref-scan's `-o` match already pulls the brain-root path out of them); `/walk` in
the checked-off history entries of `ROADMAP.md`; `json.load(open(...))` without a context manager
in `score-routing-run.py`.

## What shipped

- Tracker hygiene: public #16, #17, #19 and #20 were closed as already fixed, #21 as roadmapped, and #29 as by design (D4). GitHub keeps an issue's original body and no API deletes a revision, so scrubbing an issue by editing it does not work; the fix recorded on the deleted #30 was re-filed, closed, as pub #35. Follow-ups filed for gaps the work turned up: pub #32 (the smoke runner's sandbox keeps the reader out of intents.json), #33 (the rest of launch-email), #34 (the drift check misses upstream deletions).
- Cleanup pass: the em dash test, `ROADMAP.public.md` fixes, the README version
  sentence, the `canon-health.sh` dead variable, and the `__pycache__/` ignore.
- Steps 1-4: the ONLY-python-fence contract and its test (pub #24), brain-root paths in pipeline
  docs, `/upgrade` detection of changes shipped without a bump (pub #25), and a § reference scan
  (pub #30).
- Steps 5-6: the eval fixture manifest pinned by a test (pub #27), and `gen-manifest.sh` escaping
  every string and refusing to write invalid JSON.
- Steps 7-9: a per-source `synced` flag the sync-health tripwire reads (pub #26), the F3/F6 wiring
  in the template, Shopify example and sync-all, and `_index.md` size limits checked from
  `indexTokens`.
- Step 10: the launch-email diagnosis (pub #28), the `no-tracker-reads` check narrowed to allow
  the index peek, and the `SKILL.md` band-gate wording tightened.
- Steps 11, 11b and the release bump: the unit-context eval run recorded (PASS; pub #18 closed), the no-em-dash
  rule in `CONTRIBUTING.md`, brainforge `0.11.0` and synapse `0.7.2`.

## Where it diverged

- Step 1: `synapse/routing/README.md` also got "it" renamed to `intents.json` and a rewrap.
- Step 3: the §1 route table in `upgrade.md` was split into an up-to-date row and an
  `UNBUMPED-CHANGE` row, or the prose would contradict the script. The bump-file hash comparison
  skips tombstoned (null) manifest entries, or any brain with a deliberate deletion would print
  `UNBUMPED-CHANGE` forever. Known edge, left as designed
  under D15: a brain left with an unreconciled FLAG-MODIFIED or FLAG-COLLISION prints
  `UNBUMPED-CHANGE` on every re-run at the same version. Nothing is written wrongly.
- Step 4: `tests/ref-scan-sections.test.sh` also runs the block over `scaffold/`, and the block
  decides **Flagged** from the saved `--apply` output, which §5 tells the operator to keep.
- Step 5: the temp repo is never committed, so `generatedFrom` stays `unborn`; the temp dir is
  named `acme-brain` so `brain` is still compared.
- Step 6: the quote-in-a-title case already passed on `main` (titles were escaped), so it
  guards a regression rather than proving a fix. The temp file is copied into place with `cat`,
  not `mv`, to keep the manifest's file mode. Dropping the `exit 0` also meant rewriting the final
  unindexed check as an `if`.
- Step 7: the `$comment` in `scaffold/.claude/settings.json` was updated to match the hook.
  `scaffold/.brainforge/README.md` still describes the tripwire by `lastFullSync` only, since it
  is in no step's file list. The tripwire test also covers the `source: TODO` rule and a fresh
  scaffold.
- Steps 8-9: adapters use the template's exact `"synced"` wording for Step 8's grep. The
  Shopify example's new `acceptedSize` entry is a placeholder (`catalog.md` at 5200 tokens) in the
  template's shape. The bold lead of `sync.md`'s domain-total paragraph was cut to "Then check the
  domain total." because the caveat it quoted was removed. An
  `_index.md` envelope resolves `acceptedSize`, then the adapter row, then the 8k default, so the
  existing `acceptedSize` advice still works for index files. `gen-manifest.sh` emits `indexTokens`
  at `:215` after Step 6, not `:207`.
- Step 10: runs opened both `tracker/_index.md` (5/5) and `milestones.md` (2/5), so both
  fixes were applied. Not fixed: the smoke runner's `--restricted` sandbox blocks the reader from
  `synapse/routing/intents.json` on every case; `says-customers` fails 4 of 6 runs, so launch-email
  still fails overall; the check only watches Read calls, not Grep.
- Step 11: the unit-context pass carries the same runner caveat, so it shows the reader reached
  the unit domain, not that the new intent line routed it. Eval spend came to 7 runs (about $1.86)
  against D9's "about 6".
- Step 11b: `tests/` is not published, so the `CONTRIBUTING.md` line does not name
  `tests/public-docs.test.sh` (the public repo has no such file). It lists the five docs and says a
  check enforces the rule before each release. Step 11b's Verify grep for the file name no longer
  applies; `tests/public-docs.test.sh` still passes.

## Plan

### Step 1: Say "ONLY python fence", and test it (pub #24)

Files: `commands/upgrade.md`, `synapse/routing/README.md`, new `tests/fence-contract.test.sh`
Change: In `upgrade.md:68` change "it must remain the FIRST ```python block in this file" to say
it must be the ONLY one, and give the reason: the awk range joins every python fence. In
`synapse/routing/README.md:15-20`, stop naming "hook + sed" as the consumer. Name `coverage.sh`,
which the hook hands off to (`session-start.sh:121,155`). The new test takes optional file paths
as arguments and defaults to `commands/upgrade.md`, `commands/publish.md` and
`synapse/commands/subscribe.md`. For each file it asserts that exactly one line matches
`^```python$`, and names the file on failure. Leave `tests/synapse-subscribe.test.sh:9` as it
is: its awk stops at the first closing fence, so it is correct under either wording, and the new
test keeps `subscribe.md` at one fence so the two extraction styles cannot disagree in practice.
(`commands/forge.md` and the awk copies in the other tests do not state the FIRST rule, so they
need no edit.)
Verify: `bash tests/fence-contract.test.sh` → PASS. `T=$(mktemp -d); cp commands/upgrade.md
"$T/u.md"; printf '```python\nx\n```\n' >> "$T/u.md"; bash tests/fence-contract.test.sh
"$T/u.md"` → FAIL naming `u.md`. `grep -n 'FIRST' commands/upgrade.md` → no output. Then run all
of `tests/*.test.sh` → all PASS.

### Step 2: Remove `../` paths from pipeline docs

Files: `scaffold/pipeline/sync-health.md`, `scaffold/pipeline/ADAPTER-TEMPLATE.md`,
`scaffold/pipeline/examples/shopify.md`
Change: Rewrite each `../` path as a path from the brain root. That is all of them on `main`:
`sync-health.md:31` (`../pipeline/README.md` → `pipeline/README.md`), `ADAPTER-TEMPLATE.md:8,21`
(`../README.md` → `pipeline/README.md`), `ADAPTER-TEMPLATE.md:120` (`../README.md` →
`pipeline/README.md`; leave `adapters/<source-type>.md` on that line alone), and
`examples/shopify.md:5` (`../ADAPTER-TEMPLATE.md` → `pipeline/ADAPTER-TEMPLATE.md`). Forms
without `../`, such as `adapters/github.md`, are out of scope (see Non-goals).
Verify: `grep -rnE '\]\(\.\./|`\.\./' scaffold/pipeline` → no output (five hits on `main`). Run
the ref-scan regex from `commands/upgrade.md:220` over `scaffold/` → `pipeline/README.md` from
`ADAPTER-TEMPLATE.md:8,21,120` and `pipeline/ADAPTER-TEMPLATE.md` from `examples/shopify.md:5`
now appear in its output. (`sync-health.md:31` already appears on `main`, because `-o` pulls
`pipeline/README.md` out of `../pipeline/README.md`.)

### Step 3: `/upgrade` notices changes shipped without a version bump (pub #25; D15)

Files: `commands/upgrade.md` (the one python fence), new `tests/upgrade-unbumped.test.sh`
Change: Today `upgrade.md:106` prints `UP-TO-DATE` and exits as soon as the versions match. Only
exit when the versions match *and* every shipped bump file's hash equals its manifest baseline.
That means building `S = tree(SCAF, emit_bytes)` before the version check. If versions match but
hashes differ, print `UNBUMPED-CHANGE\t<V>\t<n> file(s)` and carry on into normal
classification. Per D15, do not read `emitted-from`. The test emits a brain at version V, changes
one scaffold bump file without bumping, and runs the classifier. Use the extract-and-run pattern
in `tests/upgrade-remove.test.sh:9`.
Verify: `bash tests/upgrade-unbumped.test.sh` → PASS: it prints `UNBUMPED-CHANGE`, and the
changed file classifies as an update. An unmodified brain still prints `UP-TO-DATE`. Against
`main`'s `upgrade.md` the same test fails, because the changed brain prints `UP-TO-DATE`. `bash
tests/fence-contract.test.sh` → PASS.

### Step 4: Ref-scan checks § references (pub #30)

Files: `commands/upgrade.md` §5 (bash only), new `tests/ref-scan-sections.test.sh`
Change: Only check `<path> § <section>` pairs whose path is in the same runtime-path set as the
existing scan at `upgrade.md:220` (`pipeline|.claude/commands|authoring|setup`). References to
files a brain never contains, such as `DESIGN.md §9` at `sync.md:42`, are out of scope. On
`main` those pairs are `pipeline/sync-health.md:31`, `pipeline/ADAPTER-TEMPLATE.md:72`,
`setup/README.md:84,85`, and in `.claude/commands/`: `add-source.md:14`, `sync-health.md:18`,
`sync.md:47,59`, `approve-canon.md:19`, `forge.md:20`. Step 2 adds `ADAPTER-TEMPLATE.md:21`.
A section is either named (`§ Defaults`) or numbered (`§1`, `§1a`, `§2`, `§3`; `§0a-bis` is used
elsewhere in the scaffold). Between the path and `§` there may be a closing backtick and one or
more spaces (`sync.md:47`: `` `setup/README.md` §1a ``; `setup/README.md:84`: `authoring/README.md
§1`). The numbered token is the run of letters, digits and `-` straight after `§`, so it includes a
suffix like `-bis` and stops at anything else, including the `>` in `ADAPTER-TEMPLATE.md:72`'s
`§1a>`. A named token is the run of letters after `§ `. Headings look
like `## Defaults — …`, `## 1a. Kinds — …` and `## 0a-bis. Read the FETCHED REF`. So a numbered
section `§<n>` matches `^#+ +<n>\.`, and a named section `§ <Word>` matches `^#+ +<Word>`. Add a
bash block to §5 that pulls out each pair, resolves the path from the brain root, and greps the
target for the heading. Each miss gets a checklist line in the PR body. A miss whose target was
flagged or deleted this run is marked **Flagged**, the word §5 and the PR template already use.
Verify: `bash tests/ref-scan-sections.test.sh` → PASS on a fixture with one good named reference,
one good `§0a-bis`-style reference and one broken reference, and it names only the broken one.
Run the block with `scaffold/` as the brain root → no misses. `bash tests/fence-contract.test.sh`
→ PASS.

### Step 5: Pin the eval fixture's manifest (pub #27)

Files: `evals/fixtures/acme-brain/.brainforge/brain-manifest.json`, new
`tests/fixture-manifest.test.sh`
Change: Copy the fixture into a temp git repo, run `scaffold/.brainforge/gen-manifest.sh`, and
commit the output as the fixture's manifest (schema 3, with `contextRoot`,
`contextFingerprint`, `unindexed`). The test does the same regeneration and diffs it against the
committed file, ignoring the lines that depend on the temp repo (`remote`, `generatedFrom`,
`generatedAt`, `contextFingerprint`; `brain` if the temp dir name leaks in).
Verify: `bash tests/fixture-manifest.test.sh` → PASS. Append ten words to one fixture doc → FAIL.
Swapping a word for another is not a valid check: tokens are counted from words, and the
fingerprint is ignored, so the test would still pass.

### Step 6: `gen-manifest.sh` escapes everything and exits non-zero on bad output (D5)

Files: `scaffold/.brainforge/gen-manifest.sh`, `tests/gen-manifest.test.sh`
Change: Make `escape_json` (`:135`) also turn tab, newline and carriage return into `\t`, `\n`
and `\r`, and strip other control characters. Pass each `kinds` item through it: today `:168`
wraps the raw items in quotes. Escape `brain` and `remote` at `:226-227`. Write to a temp file.
If `command -v python3` succeeds, run `python3 -m json.tool` on it; on failure print what failed,
remove the temp file, leave the previous manifest alone and `exit 1`. If `python3` is absent,
skip the check. Move the temp file into place, replacing the unconditional `exit 0` at `:257`
with a normal exit. Add test cases for a backslash in `kinds`, a quote in a title, and a tab in the
brain name, each checked with `python3 -m json.tool`.
Verify: `bash tests/gen-manifest.test.sh` → PASS, including the new cases, which fail against
`main`'s script. `bash tests/fixture-manifest.test.sh` → PASS, which proves the output format did
not change. `bash tests/synapse-hook.test.sh` → PASS.

### Step 7: Per-source sync flag (pub #26; D3)

Files: `scaffold/.claude/settings.json` (the sync-health hook, third in `SessionStart`),
`scaffold/.claude/commands/sync.md` (`:22-26`), `scaffold/.claude/commands/add-source.md`
(step 4, `:18`), `scaffold/.sync-state.json` (`$comment` only),
`scaffold/pipeline/adapters/{figma,github,ga,monday,website}.md` (the `lastFullSync` lines at 106,
113, 107, 103 and 40), new `tests/sync-tripwire.test.sh`
Change: `add-source.md` step 4 writes the new source's slot in `.sync-state.json` with `"synced":
false` inside it. `sync.md` and each adapter set it to `true` on success, alongside
`lastFullSync`. The sync-health hook fires on any `"synced": false`, on its existing
`lastFullSync: null` rule, or on its existing `source: TODO` check in `context/derived`. Keep the
check grep-only and valid for any org name. Update the `.sync-state.json` `$comment` to describe
the flag. The format contract still applies: multi-line, one key per line. For the test, pull the
hook command out of `settings.json` the way `tests/org-name-safety.test.sh:13-20` does (python3
loads the JSON and writes each `SessionStart` command to its own script file). Then run the third
script with `CLAUDE_PROJECT_DIR` pointed at a temp brain.
Verify: `bash tests/sync-tripwire.test.sh` → the tripwire fires for (a) a brain that has never
synced, (b) a brain where one source is `"synced": false` but `lastFullSync` is set, and (c) an
old-format brain with no flag field and `lastFullSync: null`, exactly as on `main`. It is silent
for a fully synced brain. Case (b) fails against `main`'s hook. `bash
tests/org-name-safety.test.sh` → PASS.

### Step 8: Finish the F3/F6 wiring

Files: `scaffold/pipeline/ADAPTER-TEMPLATE.md` (`:82-85`), `scaffold/pipeline/examples/shopify.md`
(`:75-82`, `:94-107`), `scaffold/pipeline/sync-all.md` (`:12`, step 5)
Change: Add the Step 7 sync-state update (set the source's `"synced": true` and `lastFullSync`)
to the template's completion step, the Shopify example's state update, and sync-all step 5. Add
`cadence` and `acceptedSize` to the Shopify example's `sources.json` entry, in the shape
`ADAPTER-TEMPLATE.md:106-107` gives. No shipped adapter carries that entry.
Verify: `grep -n lastFullSync scaffold/pipeline/ADAPTER-TEMPLATE.md
scaffold/pipeline/examples/shopify.md scaffold/pipeline/sync-all.md` → at least one hit in each
(none of the three has one on `main`). `grep -n '"synced"'` on the same
three files → one hit each. `grep -nE 'cadence|acceptedSize' scaffold/pipeline/examples/shopify.md`
→ both present. Read the three sections against `ADAPTER-TEMPLATE.md` to confirm they match.

### Step 9: Enforce `_index.md` size limits (D6, D16)

Files: `scaffold/.claude/commands/sync.md` (`:61-62`), `scaffold/pipeline/README.md`
(`:78-82`), `scaffold/pipeline/ADAPTER-TEMPLATE.md` (`:31-34`), new `tests/sync-rules.test.sh`
Change: In `sync.md`, replace the "an `_index.md` has no `tokens` figure" paragraph with a rule
that reads the domain's `indexTokens` from the manifest. Check it against the adapter's
`_index.md` envelope row, and include it in the 3× growth check against `$PREV`, using the same
`⚠ rule-6:` line format. Delete the caveat paragraph in `pipeline/README.md:78-82` and the one
in `ADAPTER-TEMPLATE.md:31-34`, replacing each with one sentence saying `/sync` checks
`_index.md` rows from `indexTokens`. The new test (D16) asserts that none of these three
sentences remain: `Rule 6 cannot be applied to one` in `sync.md`, ``a per-`_index.md` envelope
does not fire yet`` in `pipeline/README.md`, and ``row is a **manual** check for now`` in
`ADAPTER-TEMPLATE.md`. Use `grep -F` so the backticks and asterisks match literally.
Verify: `bash tests/sync-rules.test.sh` → PASS; against `main` it fails, naming all three.
`grep -n indexTokens scaffold/.brainforge/gen-manifest.sh` → the field is still emitted (`:207`).
There is no harness that runs the command's prose, so `critic` also reads the new rule against
the shape of the domain-total check at `sync.md:71-77`.

### Step 10: Diagnose the launch-email eval failures (pub #28; D9)

Files: likely `synapse/evals/routing/launch-email/case.yaml` (`:40-45`) or
`synapse/skills/*/SKILL.md` (the band-gate rule near `:34`, the announce rule near `:59-64`)
Change: The deliverable is a diagnosis written on pub #28; a fix follows only if the diagnosis
calls for one. Run `bash synapse/evals/routing-smoke.sh launch-email` and record which `tracker/`
file the run opens. If it is `tracker/_index.md`, the check predates the rule that allows it (check
f66ed23, rule 8ebbf7d): narrow `no-tracker-reads` to leave out `_index.md` (an eval file, no
synapse bump). If it is `milestones.md`, the reader is breaking the band gate: fix the `SKILL.md`
wording, which needs the synapse bump in the release (D13). For the announce-line failure, run the
case 5 times in total and record the pass rate.
Closing #28: if a fix was made, the release closes it with a link to the PR. If no fix was made and
all 5 runs passed, close it now with the diagnosis comment as the reason. If the announce line
still fails some runs with no fix, open a new issue for that flake alone (the measured rate, the
rule at `SKILL.md:59-64`), then close #28 with a link to the new issue.
Verify: `gh issue view 28 -R jrpease/brainforge --comments` → a comment with the tracker file
opened, the announce-line pass rate over 5 runs, and the change made (or "none"). If a fix was
made, the next `bash synapse/evals/routing-smoke.sh launch-email` run passes the check that was
fixed. If no fix was made, `gh issue view 28 -R jrpease/brainforge --json state --jq .state` →
`CLOSED`.

### Step 11: Run the unit-context eval (pub #18; D9)

Files: `docs/specs/2026-09-09-audit-hardening.md` (the note at `:241-246`)
Change: Run the one eval that spec lists as outstanding. Under that note, add one line in the
form `**Eval run (YYYY-MM-DD):** unit-context PASS via synapse/evals/routing-smoke.sh`, and commit
it with the release. A failure becomes its own issue, not a fix inside
this plan.
Verify: `bash synapse/evals/routing-smoke.sh unit-context` → PASS. `grep -n 'Eval run ('
docs/specs/2026-09-09-audit-hardening.md` → one hit (none on `main`). Close pub #18 with the
result.

### Step 11b: State the no-em-dash rule where contributors read (D11)

Files: `CONTRIBUTING.md`
Change: One line under `## PR expectations` (`:94`): the five authored public docs carry no em
dashes, and `tests/public-docs.test.sh` checks it. Docs-only, so it needs a re-release but no bump.
Verify: `grep -n 'public-docs.test.sh' CONTRIBUTING.md` → one hit, below `:94` (none on `main`).
`bash tests/public-docs.test.sh` → PASS, so the new line carries no em dash itself.

**Good fits for `implementer`:** Step 2 (a five-line path rewrite) and Step 8 (the same insertion
in three files). Steps 3, 4, 6 and 7 change contract logic and should be done inline with their
tests.
