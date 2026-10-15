# Brainforge Studio

A local admin app for a [Brainforge](https://github.com/jrpease/brainforge) brain. Run it inside a
brain and it shows you what needs attention, lets you browse everything the brain holds, and lists
its sources.

```bash
cd path/to/your-brain
npx brainforge-studio
```

It prints a link and opens it. That link carries a one-time key for this launch, so keep using it
rather than typing the address by hand.

## What it shows

- **Health.** What needs you: canon past its review date or never reviewed, drift between canon and
  synced facts, sources that never synced. "Check sources now" asks each source whether it changed
  upstream. Every item comes with the Claude Code command that fixes it.
- **Brain.** Every domain in the brain's manifest; open any doc to read it.
- **Sources.** What `sources.json` and `.sync-state.json` record, as they are.

## What it never does

It never writes to your brain. Every verdict comes from the brain's own scripts in `.brainforge/`.
Changes still happen in Claude Code, through the brain's commands and their PRs.

It listens on `127.0.0.1` only, and every request needs the launch key.

## Needs

Node 20 or later, git, and python3 (the brain's source checks use it). Studio checks these when it
starts and tells you what's missing. GitHub CLI and Claude Code are needed for later versions.

## Options

```
brainforge-studio [brain-path] [--port <n>] [--no-open]
```

`BRAINFORGE_STUDIO_NO_OPEN=1` also stops it opening a browser.

An older brain shows "run /upgrade" on any panel it doesn't support yet.

MIT licensed.
