# Snippet: set up a personal/team WORKSPACE that reads this context

Your creative work — brainstorming, drafts, generated artifacts — happens in a **separate
workspace folder**, not in the context repo. This keeps the source of truth pristine and gives
you (and every teammate) the same read-only consumption experience.

## 1. Make a workspace folder (anywhere outside the context repo)
e.g. `~/Documents/Claude/Projects/{{ORG}} Workspace/`

## 2. Add this to the workspace's `CLAUDE.md`

```markdown
## How to use {{ORG}} context here

The {{ORG}} source of truth is at <path-or-url> (clone or GitHub).

- Treat it as **read-only reference.** Read from `context/canon/` (trusted truth) and
  `context/derived/` (synced facts — check `last-synced`).
- **Write all outputs into THIS workspace, never into the context repo.**
- When I ask you to create/brainstorm, ground it in the canon (voice, naming, principles) and
  cite which context file informed the result.
- If derived `last-synced` looks old, say so rather than asserting it as current.
```

## 3. Keep the context fresh
If you cloned the context repo, it auto-pulls on session start (its `.claude/settings.json`
ships an auto-pull hook). Otherwise, point at the GitHub copy.
