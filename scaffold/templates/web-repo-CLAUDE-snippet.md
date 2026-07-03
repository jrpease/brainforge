# Snippet: add this to your WEB REPO's `CLAUDE.md`

Paste the block below into the `CLAUDE.md` of the website (or any product repo). It teaches any
LLM working there to **reference** {{ORG}}'s canon instead of copying it — so there's one source
of truth, and every session auto-knows to consult it.

Replace `<path-or-url>` with either a local clone path (e.g. `../{{ORG}} Design`) or the GitHub
URL of the context repo.

```markdown
## {{ORG}} brand & product source of truth

Canonical brand voice, messaging, naming, product principles, and design intent live in the
{{ORG}} context repo: <path-or-url>/context/canon/

- **Read `context/canon/brand/` before writing any user-facing copy or naming anything.**
- **Read `context/canon/design/design-principles.md` before making design decisions.**
- This repo's own code conventions and component APIs are the source of truth for *themselves* —
  keep those here.
- **Do NOT copy canon content into this repo.** Link to it. One source of truth, referenced.
- If the canon looks wrong or stale, suggest a change in the context repo (see its
  CONTRIBUTING.md) — don't fork the truth here.
```

> Optional, for tighter coupling: add the context repo as a **read-only git submodule** so the
> canon is physically present (pinned to a commit, no drift). Only do this if the loose pointer
> proves insufficient — submodules add overhead for everyone.
