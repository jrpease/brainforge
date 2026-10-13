# Public-install smoke test: live proof

Run 2026-10-13, stranger-style, in a throwaway Claude profile (`CLAUDE_CONFIG_DIR` and
`SYNAPSE_HOME` both under a temp directory), from the public marketplace: brainforge 0.15.1 and
synapse 0.8.0. Each step is a `claude -p` session, with answers given in the next turn via
`--continue`. Fake org: Smokeco. This was issue #1, the last gate for "publicly usable". It
also served as the website adapter's first live proof.

## Results

| # | Step | Result | What happened |
|---|---|---|---|
| 1 | Versions | PASS | `brainforge@brainforge` 0.15.1 and `synapse@brainforge` 0.8.0, installed from `jrpease/brainforge` |
| 2 | `/brainforge:forge` | PASS | Asked to `git init` and for the org name before any write. Emitted 56 files with the heading `# Smokeco — Shared Context`; runtime manifest at 0.15.1 (36 files, all adopted clean); one commit. Warned up front that pushing a workflow file needs the `workflow` token scope |
| 3 | `/forge`, `/draft-canon eng/architecture-decisions`, `/approve-canon` | PASS | The wizard laid out every domain's status and recommended eng first. The draft invented nothing: 8 `[GAP]`s where the input gave no reason, and approval was refused until they were filled. Approval set `status: approved`, `last-reviewed: 2026-10-13`, kept `review-cadence: quarterly`, and regenerated the manifest |
| 4 | `/add-source` a website, `/sync`, `/sync` again, `/sync-health`, `/canon-health` | **FAIL** (second `/sync`) | Details below |
| 5 | Push to a new private repo | PASS | The manifest Action ran green in 11s with no bot commit, so the map computed on macOS matched the runner's |
| 6 | Subscribe from an unrelated folder; eng and brand questions | **FAIL** (eng) | Details below |

### Step 4

- `/add-source` refused "home page only" because the adapter tracks a sitemap and no field limits
  that scope. It also caught that `example.com` has no sitemap at all. The source became
  choosealicense.com (55 sitemap URLs), tracking the whole site.
- The first `/sync` fetched all 55 URLs and wrote `site-map.md`, `home.md` and `_index.md` (no
  kinds; it proposed `site-inventory` for a human to confirm). It ran the rule-6 size check and
  regenerated the map.
- **The second `/sync` was not a no-op.** The gate flagged 11 pages; all 11 re-fetched identical,
  and the sync committed refreshed etags. Cause: the site's CDN serves the same bytes from two
  origins with different ETags (`"6ac03420-63ba"` and `"6ac0352c-63ba"` for one page). A
  conditional GET that carries the other origin's ETag returns 200, and the gate counted every
  200 as changed.
- `/sync-health` reported the source ⚠ behind and said itself that people would learn to ignore
  it. `/canon-health` was clean (1 approved doc, within cadence), and it said plainly that one
  doc proves little.

### Step 6

- `/synapse:subscribe` wrote to `$CLAUDE_CONFIG_DIR/settings.json` and probed access. The next
  session's map showed both domains.
- **Eng question ("Should I add Redis for our background job queue?"): every read refused.** The
  answer said so ("I couldn't check your brain on this… read permission declined"), announced
  `loaded: none`, and gave a generic answer. Two grants were missing: subscribe granted
  `~/.synapse` whatever `SYNAPSE_HOME` said, and nothing granted synapse's own
  `routing/intents.json`. With both granted by hand, the same question answered from the ADR
  ("No. Your team already decided against it. ADR-3…").
- Brand question ("Write the tagline for our homepage hero, in our brand voice."): PASS. It said
  the brain had no brand-voice content and labelled its drafts "not checked against any voice
  guide".

### Friction a stranger would hit

- Canon lands through a PR, and the issue pushes only at step 5, so approved canon waits on a
  branch until there is a remote.
- The `workflow` token scope for the first push (covered by the bootstrap's warning; this
  run's token already had it).

## Fixes

Spec: [`2026-10-13-smoke-test-fixes.md`](../specs/2026-10-13-smoke-test-fixes.md).

## Re-run after the fixes

Same day, same smoke brain and profile, with brainforge 0.15.2's gate and synapse 0.8.1's
subscribe script run from this checkout:

- **Website gate, live against choosealicense.com.** `gate-website.sh --fingerprint
  marketing-site` printed `status: fingerprint` with 55 of 55 pages hashed. With that stored,
  three plain gate runs in a row printed `unchanged` with an empty delta. Before the fix each run
  flagged 9 to 11 pages.
- **Subscribed reader.** The throwaway `settings.json` was reset to before the subscription, then
  the command's own `bf-subscribe.py` ran with `--plugin-root` set to the installed synapse. It
  printed `dirs: <SYNAPSE_HOME>` and `read: Read(//…/plugins/cache/brainforge/synapse/**)`. A new
  session asked the step-6 eng question, read `eng/_index.md`, `routing/intents.json` and
  `architecture-decisions.md` with no refusal, and answered "No, not by default. Your team has
  already made this call", citing ADR-3, with `🧠 loaded: Engineering`.

Still open: an interactive session sees one Bash prompt per brain question, because the
brain-routing skill's first attempt is a compound `cat` before it falls back to Read. Fixing that
is a skill change and needs a routing eval run.
