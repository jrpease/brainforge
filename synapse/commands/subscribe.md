---
description: Subscribe this user to a Brainforge brain — records it in personal settings so every future session auto-pulls it and shows its map.
argument-hint: <brain-git-url-or-path>
---

# /subscribe — follow a brain from every session

Records a brain subscription in the user's **personal** settings (`~/.claude/settings.json`).
From the next session on, the synapse SessionStart hook clones/pulls the brain and renders its
map in every session, in any repo or folder. This command only writes the subscription — the
hook does the cloning.

**Arguments:** exactly one — the brain's git URL (e.g. `git@github.com:org/brain.git`) or an
absolute local path to a brain checkout.

## 0. Guard

If no argument was given, ask the user for the brain's git URL and stop until they provide it.
Never guess a URL.

## 1. Run the subscriber

Extract the **first** ```python fence in this file to `$TMPDIR/bf-subscribe.py` and run:

```
python3 $TMPDIR/bf-subscribe.py "<the-url-argument>"
```

(The fence position is load-bearing — same extraction convention as `commands/upgrade.md`.)
The script is deterministic and self-contained: it merges into `~/.claude/settings.json`
(creating it if absent), preserves every existing setting, appends to `SYNAPSE_BRAINS`
(comma-separated, deduplicated), ensures `~/.synapse` is in `permissions.additionalDirectories`,
and refuses to touch a settings file it cannot parse. It never edits project/repo settings.

```python
#!/usr/bin/env python3
"""bf-subscribe.py <brain-url> [--settings <path>]

Merge a brain subscription into the user's personal Claude settings.
Deterministic; stdlib only. --settings overrides the target file (tests).
"""
import json, os, subprocess, sys


def norm(u):
    return u.rstrip("/")


def main(argv):
    args = list(argv)
    path = os.path.expanduser("~/.claude/settings.json")
    if "--settings" in args:
        i = args.index("--settings")
        path = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1 or args[0].startswith("-"):
        print("usage: bf-subscribe.py <brain-git-url-or-path> [--settings <path>]")
        return 2
    url = args[0]

    # Access probe — informative, never fatal: the hook re-checks every session anyway.
    access = "unverified"
    try:
        r = subprocess.run(["git", "ls-remote", url, "HEAD"],
                           capture_output=True, timeout=15)
        access = "ok" if r.returncode == 0 else "failed"
    except Exception:
        access = "failed"

    settings = {}
    if os.path.exists(path):
        try:
            with open(path) as f:
                settings = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            print(f"ERROR: {path} exists but is not valid JSON ({e}).")
            print("Refusing to overwrite it — fix the file by hand, then re-run /subscribe.")
            return 1

    env = settings.setdefault("env", {})
    current = [b.strip() for b in env.get("SYNAPSE_BRAINS", "").split(",") if b.strip()]
    if norm(url) in {norm(b) for b in current}:
        print(f"already subscribed: {url}")
    else:
        current.append(url)
        env["SYNAPSE_BRAINS"] = ",".join(current)

    dirs = settings.setdefault("permissions", {}).setdefault("additionalDirectories", [])
    if "~/.synapse" not in dirs:
        dirs.append("~/.synapse")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)

    print(f"subscribed ✓  {path}")
    print("brains: " + env["SYNAPSE_BRAINS"])
    if access == "failed":
        print(f"⚠ access: could not reach {url} — you may need GitHub read access to the "
              "brain repo. The subscription is saved; sessions will say UNGROUNDED until "
              "access works.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

## 2. Relay and close

Relay the script's output verbatim. Then:

- If it printed `⚠ access`, tell the user plainly: they need read access to the brain repo
  (normal GitHub org membership) before sessions can ground — the subscription itself is saved.
- Finish with: **restart this session (or open a new one)** — the synapse hook clones the
  brain at session start and shows its map. Nothing appears until then.
