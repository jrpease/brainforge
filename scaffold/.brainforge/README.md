# `.brainforge/` — manager-layer state

Small bits of **manager (day-2) state** that are neither canon nor derived context.

## `last-drift-review`

A single line: the **git commit SHA** at which authored canon was last reconciled against derived
reality (the `/drift` run's `HEAD` at completion). It is the watermark for the session-start drift
gate:

- The `SessionStart` hook (see `.claude/settings.json`) cheaply asks *"has `context/canon/` or
  `context/derived/` changed since this SHA?"* — if yes (or if this file is missing on a brain that
  already has derived content), it nudges you to run `/drift`.
- `/drift` **writes** this file at the end of every run (drift found or not), so the nudge clears
  until the next canon edit or sync.

It is a **plain one-line file, not a field in `.sync-state.json`, on purpose** — so the shell hook can
read it with `cat` and needs no `jq`/python. It is committed so the watermark travels with history.
Do not hand-edit it; `/drift` owns it.

## No file for the sync-health tripwire (by design)

The session-start **sync-health tripwire** (see `.claude/settings.json`) nudges you to run
`/sync-health` when a source is wired but never synced (`.sync-state.json` has a populated
fingerprint slot while `lastFullSync` is still `null`) or a derived doc still carries
`source: TODO`. Unlike `last-drift-review`, it stores **nothing here** — it reads live repo
state each session and **self-clears the moment the problem is fixed** (the first successful
sync, or the filled-in source). The drift gate clears on *acknowledgment* (running `/drift`
stamps the watermark); the sync-health gate clears only on *resolution*. Different semantics,
so: a watermark for drift, no state for sync health.

## `runtime-manifest.json`

Written by the **emission contract** (at scaffold time and by every builder-side `/upgrade`): the
Brainforge plugin `runtime-version` plus a sha256 per shipped **bump** file (the seam declared in
the plugin's `runtime.bump`), hashed **as emitted** — i.e. after the scaffold's org-name placeholder
is templated in (the same substitution that turns the scaffold into this brain). It is
the baseline that lets a later `/upgrade` decide per file, deterministically: byte-unmodified →
safe to overwrite with the new version; locally modified → flag in the upgrade PR, never clobber;
not shipped at all → yours, never touched.

It is **JSON, unlike the plain-line watermark above, on purpose**: no shell hook ever reads it —
only the LLM-driven builder-side `/upgrade` does — so the jq-free constraint doesn't apply. It is
committed so baselines travel with history. Do not hand-edit it; the emission contract owns it.

## `brain-manifest.json`

The **consumer map** — what a reader needs to know before opening any file: every domain under
`context/`, its `kinds`, and a token count/band per domain and per file. It is a **core brain
artifact**, regenerated on every sync (not only on demand), and is what the synapse reader plugin
and tier-2 pointer snippets consult to route a prompt to the relevant slice instead of loading the
whole brain. Do not hand-edit it; it is regenerated, never authored.

**`"schema": 2`** — token accounting is honest. Schema 1 counted only `*.md` excluding
`_index.md`, so every domain under-reported its real read cost: index files and emitted data
files (e.g. `design-system/tokens.json`) were invisible. In one real brain that hid ~10,000
tokens across `context/` (33,031 reported vs 43,386 actual), enough for a domain to sit in the
`cheap` band while actually being `normal`. Per domain you now get:

| Key | Meaning |
|---|---|
| `tokens` | `docTokens + indexTokens` — the honest total; **bands are computed from this** |
| `docTokens` | sum of `files[]` — what schema 1 called `tokens`, kept for continuity |
| `indexTokens` | the domain's own `_index.md` |

`files[]` now also lists `*.json` data files. **Line format is unchanged** (single-line objects,
2-space indent), so `grep`/`sed`/`awk` consumers keep working — only the arithmetic changed, which
is why a brain still on schema 1 stays readable by the same hooks. Note the estimator is
word-based (`words * 4 / 3`), tuned for prose and under-counting punctuation-dense JSON: treat
`.json` figures as a floor.

**`"schema": 3`** — the map can finally say whether it is current, and where it looked.

Schema 2 stamped `generatedFrom` = `HEAD`. You then had to *commit* the manifest, which creates a
new `HEAD`, so the reader's staleness check could never pass: the commit that lands a fresh map is
the commit that invalidates it. The warning was on permanently, on every healthy brain, and a
warning that is always on is not a warning — people learn to scroll past it.

No commit sha fixes that. `/sync` lands the derived change and the regenerated manifest in **one**
commit, so the sha carrying the manifest cannot be known while the manifest is being written.
(Under the sha scheme that also ruled out a CI job. Under *this* scheme it does not: a
post-merge job that regenerates and commits touches only `.brainforge/`, leaving the context
tree — and therefore the fingerprint — unchanged. That makes CI regeneration the clean fix for
two PRs conflicting on the manifest, which they otherwise always do.) Two keys replace it:

| Key | Meaning |
|---|---|
| `contextRoot` | the directory domains were found under — `BRAIN_CONTEXT_DIR`, default `context` — so a reader never has to assume it |
| `contextFingerprint` | the git **tree object id** of that root, as the generator saw it |

**FINGERPRINT CONTRACT.** The fingerprint is the git tree oid of `contextRoot`, and nothing else.
A reader recomputes it as `git rev-parse HEAD:<contextRoot>` and compares. Identical content gives
an identical oid because git trees are content-addressed, so this holds across commits, rebases
and squashes — including the same-commit case above — and the read side is a single `rev-parse`
with no file hashing. `gen-manifest.sh` and the synapse hook both encode this definition. Change
one and you change the other in the same breath, or the warning comes back on permanently in the
other direction.

`generatedFrom` is **kept, as provenance only.** Nothing compares against it any more.

**`contextRoot` precedence, and its limits.** The generator takes the root from
`BRAIN_CONTEXT_DIR`, else from the `contextRoot` already recorded here, else `context`. The
read-back matters: the env var is not committed and every documented regenerate path (`/sync`,
`/upgrade` §5a, the command below) calls the generator bare, so without it a non-default root
silently reverted and emitted a zero-domain map.

`BRAIN_CONTEXT_DIR` exists so a **source repo** whose docs do not live under `context/` can emit
a valid manifest for a reader. It is not a general setting for a brain. The brain-side hooks in
`.claude/settings.json` — the drift gate and the sync-health tripwire — assume `context/canon`
and `context/derived` literally, so a brain that moves its root loses both without a word. Move
a brain's root only if you are also prepared to change those two hooks.

An empty `contextFingerprint` means *not computable*, which a reader treats as **unknown**, never
as stale. A manifest with no such key is pre-schema-3: the reader says so and names the command
that fixes it. Both clear on the next run of the generator.

## `gen-manifest.sh`

The **deterministic generator** for `brain-manifest.json`. No LLM, no network — `git`/`find`/`sed`/
`awk`/`wc` only (golden rule 3). Run it with `bash .brainforge/gen-manifest.sh`; every sync command
runs it as a final step so the manifest never drifts from the brain it describes.
