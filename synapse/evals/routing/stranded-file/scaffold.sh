#!/usr/bin/env bash
# Seeds the eval harness's sandbox cwd with the acme-brain fixture, so the
# sandbox cwd IS a brain (has .brainforge/brain-manifest.json at its root) —
# exercising SKILL.md's "cwd is itself a brain" path, not SYNAPSE_BRAINS.
# The harness runs this script with cwd already set to the sandbox cwd; we
# locate the fixture relative to this script's own path so it works from any
# checkout location. (scaffold_script paths are sandboxed to the case
# directory, so this file is duplicated per case rather than shared.)
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(cd "$here/../../../../evals/fixtures/acme-brain" && pwd)"
cp -R "$fixture"/. .
