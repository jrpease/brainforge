---
description: Audit a brain's routing coverage — content the router cannot reach, and expensive domains behind a single intent.
argument-hint: [brain-path-or-manifest]
---

# /coverage — is every doc reachable by the questions it answers?

Routing runs on the `kinds:` each domain declares, matched against the intent table. A kind no
intent points at makes its whole domain invisible, and the only symptom is a confidently wrong
answer sourced from somewhere else. This command is the join that finds it — deterministic, no
LLM, no network, two files.

It reads. It never writes, never opens a PR, and never edits a brain.

**Arguments:** `$ARGUMENTS` — optional. A brain checkout, a manifest path, or nothing.

## 1. Find the manifest

In order, first hit wins:

1. `$ARGUMENTS` — a `brain-manifest.json`, or a directory to append
   `.brainforge/brain-manifest.json` to.
2. The current working directory, if it is itself a brain (`.brainforge/brain-manifest.json`).
3. Each subscribed brain shown in this session's map. **Use the path the map printed** — never
   reconstruct it from the brain's name, because collision-suffixed directories exist. With
   more than one subscribed brain and no argument, run the report for each in turn.

None of the three → say so plainly and stop. Do not go looking around the filesystem for some
other directory that happens to hold a manifest.

## 2. Run it

```
bash "${CLAUDE_PLUGIN_ROOT}/routing/coverage.sh" <manifest>
```

Relay the output verbatim. Exit 1 means unroutable kinds or unreachable domains; exit 0 means
clean, or narrow gates only.

## 3. Say what each finding costs, and who fixes it

Four shapes come back. They have different owners, which is the part worth saying out loud:

| Finding | What it means | Who fixes it |
|---|---|---|
| **unroutable kind** | The domain declares a kind the intent table has no entry for. Dead routing — this content never loads. | Either: the brain corrects the kind to one in the vocabulary, or Brainforge grows the vocabulary (an intent, a catalog row, an eval case, a version bump — `routing/README.md`). |
| **unreachable domain** | No declared kind any intent points at. `(declares none)` means it is also in the manifest's `unclassified` list, and `/sync` will offer to classify it. | The brain, by stamping `kinds:` in that domain's `_index.md`. |
| **narrow gate** | An `expensive` domain only one intent reaches. The band gate opens it on a direct match only, so one phrasing loads it and no other does. Not necessarily wrong — but it is how a large domain holding the only accurate doc on a subject goes unread. | Judgment. Usually a second kind on the domain, or splitting it. |
| **intents this brain cannot answer** | Informational. The questions this brain will come up empty on. | Nobody, unless the gap is a surprise. |

Do not propose kind edits as a diff or open a PR from here. Name the domain, name the fix, and
let the owner make it — a wrong kind is worse than no kind, because a wrongly-labelled domain
stops appearing in `unclassified` and becomes a silent orphan instead of a visible one.

## 4. When it is clean

Say so in one line and stop. A clean run means every domain is reachable by at least one intent
and every declared kind routes. It does **not** mean the routing is good — only that nothing is
structurally stranded.
