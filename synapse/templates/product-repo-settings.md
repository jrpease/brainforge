# Subscribe a product repo to a brain (zero-touch for teammates)

Commit this into the product repo's `.claude/settings.json` (merge with existing keys).
Anyone who opens the repo in Claude Code gets synapse + the brain after one trust prompt —
that is the entire onboarding.

```json
{
  "extraKnownMarketplaces": {
    "brainforge": {
      "source": { "source": "github", "repo": "jrpease/brainforge" }
    }
  },
  "enabledPlugins": {
    "synapse@brainforge": true
  },
  "env": {
    "SYNAPSE_BRAINS": "git@github.com:YOUR-ORG/YOUR-BRAIN.git"
  },
  "permissions": {
    "additionalDirectories": ["~/.synapse"]
  }
}
```

- `SYNAPSE_BRAINS` is comma-separated — subscribe one repo to several brains if you need to.
- Teammates need read access to the brain repo (normal GitHub org membership).
- Personal (non-repo) subscription: put the same `env` block in `~/.claude/settings.json`
  and install synapse once: `claude plugin marketplace add jrpease/brainforge` →
  `claude plugin install synapse@brainforge`.
