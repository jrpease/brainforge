# Proofs

This directory is the anti-speculation evidence for Brainforge: every adapter and feature listed
below was proven against a real system before it shipped — not just designed and asserted to work.
Each summary records what was actually run, what the run detected or extracted, and what the live
system taught the spine that got folded back in as hardening.

- [Figma adapter](figma-adapter.md) — proven live against a production design-system file.
- [Monday adapter](monday-adapter.md) — proven live against a production work-management workspace.
- [GitHub adapter](github-adapter.md) — proven live against a production web-app repo.
- [Depth-first wizard](depth-first-wizard.md) — proven live on a fresh throwaway brain.
- [CI manifest regeneration](ci-manifest-regeneration.md) — proven live on a throwaway private
  GitHub repo: direct pushes, a merge conflict on the manifest, and a protected branch.
- [Public-install smoke test](public-install-smoke-test.md) — issue #1's stranger-style loop from
  the public marketplace, in a throwaway profile; found and fixed two defects (subscriber read
  permissions, website-gate CDN flapping). Also the website adapter's first live proof.
- [MCP façade](mcp-facade.md) — proven live in Codex (no synapse code at all) and in Claude Code
  with the synapse plugin disabled, against the eval fixture brain.
- [GA adapter](2026-07-02-ga-live/README.md) — proven live against a real, trafficked GA4 property
  (the last Phase-2 adapter and the first metrics/time-series source); predates this summary format.
