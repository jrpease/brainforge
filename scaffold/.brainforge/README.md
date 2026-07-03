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
