// Comp fixtures: one per state in SCREENS.md's Health inventory. The canon text and gate lines
// copy the real scripts' formats exactly (checked against canon-health.sh and gate-*.sh output).
import type { BrainInfo, GateLine, GateRun, GatesResponse, HealthResponse } from "../../src/lib/types";

export const STATES = [
  "initial-load", "all-clear", "first-run", "single-item", "dense", "overflow", "tripwires",
  "gates-running", "gates-mixed", "gate-error", "degraded-older-brain", "canon-error", "refresh",
  "server-down", "unauthorized",
] as const;
export type StateName = (typeof STATES)[number];

export const BRAIN: BrainInfo = { name: "acme-brain", path: "/Users/sam/brains/acme-brain" };

const run = { available: true as const, stderr: "", timedOut: false };

const canonText = (summary: string, body: string) =>
  `Canon health — context/canon\n  ${summary}\n\n${body}\n`;

const CLEAN = canonText(
  "14 approved and current · 0 past review · 0 never reviewed · 3 draft(s)",
  `· drafts — not yet trusted as canon; a stalled one means the approve gate never closed
    context/canon/brand/naming.md                last touched 2026-10-09  open
    context/canon/pricing/model.md               last touched 2026-10-12  open
    context/canon/audience/archetypes.md         last touched 2026-10-14  open

✓ every approved canon doc is within its review cadence.`,
);

const FOOT = `Re-confirm a doc by reviewing it and running /approve-canon, which stamps today's date.
A doc that genuinely does not rot can declare 'review-cadence: never' in its frontmatter.`;

const DENSE = canonText(
  "9 approved and current · 4 past review · 2 never reviewed · 6 draft(s)",
  `✗ approved but never reviewed — carrying full authority on a template default
    context/canon/brand/naming.md                owner: TODO
    context/canon/eng/conventions.md             owner: TODO

⚠ past review — the date someone last confirmed this is still true
    context/canon/brand/voice.md                 2025-11-02  biannual (default)     owner: Priya
    context/canon/product/roadmap.md             2026-05-30  quarterly              owner: Sam
    context/canon/design/principles.md           2025-08-14  biannual (default)     owner: Jordan
    context/canon/company/org.md                 2024-12-01  annual                 owner: Lee

· drafts — not yet trusted as canon; a stalled one means the approve gate never closed
    context/canon/brand/arch.md                  last touched 2026-03-29  stalled
    context/canon/pricing/tiers.md               last touched 2026-06-02  stalled
    context/canon/audience/archetypes.md         last touched 2026-10-14  open
    context/canon/analytics/metrics.md           last touched 2026-10-11  open
    context/canon/product/tenets.md              last touched 2026-10-02  open
    context/canon/company/remote-work.md         last touched 2026-09-30  open

${FOOT}`,
);

const SINGLE = canonText(
  "13 approved and current · 1 past review · 0 never reviewed · 0 draft(s)",
  `⚠ past review — the date someone last confirmed this is still true
    context/canon/brand/voice.md                 2025-11-02  biannual (default)     owner: Priya

${FOOT}`,
);

const OVERFLOW = canonText(
  "10482 approved and current · 1 past review · 0 never reviewed · 1 draft(s)",
  `⚠ past review — the date someone last confirmed this is still true
    context/canon/product/platform-migration-strategy-and-sequencing-for-the-2027-replatform.md  2025-01-04  biannual (default)     owner: Alexandria Montgomery-Okafor

· drafts — not yet trusted as canon; a stalled one means the approve gate never closed
    context/canon/brand/sub-brands/enterprise/naming-conventions-for-regional-partner-programs.md  last touched 2026-02-11  stalled

${FOOT}`,
);

const FIRST = canonText(
  "0 approved and current · 0 past review · 0 never reviewed · 6 draft(s)",
  `· drafts — not yet trusted as canon; a stalled one means the approve gate never closed
    context/canon/brand/voice.md                 last touched 2026-10-15  open
    context/canon/brand/naming.md                last touched 2026-10-15  open
    context/canon/product/tenets.md              last touched 2026-10-15  open
    context/canon/design/principles.md           last touched 2026-10-15  open
    context/canon/eng/conventions.md             last touched 2026-10-15  open
    context/canon/company/org.md                 last touched 2026-10-15  open

${FOOT}`,
);

const canon = (stdout: string, exitCode = 1) => ({ ...run, stdout, exitCode, finding: exitCode === 1, error: false });
const trips = (lines: string[]) => ({ ...run, stdout: lines.join("\n"), exitCode: 0, lines, error: false });
const UPGRADE = { available: false as const, hint: "Not available in this brain; run /upgrade." };

const DRIFT = "⚠️  Context changed since last drift review — run /drift to check canon vs. reality.";
const SYNC = "⚠️  Sync health: a source is unsynced or still has a TODO — run /sync-health.";

export const HEALTH: Partial<Record<StateName, HealthResponse>> = {
  "all-clear": { canon: canon(CLEAN, 0), tripwires: trips([]) },
  "first-run": { canon: canon(FIRST, 0), tripwires: trips([]) },
  "single-item": { canon: canon(SINGLE), tripwires: trips([]) },
  dense: { canon: canon(DENSE), tripwires: trips([DRIFT, SYNC]) },
  overflow: { canon: canon(OVERFLOW), tripwires: trips([SYNC]) },
  tripwires: { canon: canon(CLEAN, 0), tripwires: trips([DRIFT, SYNC]) },
  "degraded-older-brain": { canon: canon(SINGLE), tripwires: UPGRADE },
  "canon-error": {
    canon: { ...run, stdout: "", stderr: "canon-health.sh: line 61: syntax error near unexpected token `fi'", exitCode: 2, finding: false, error: true },
    tripwires: trips([DRIFT]),
  },
};
for (const s of ["gates-running", "gates-mixed", "gate-error", "refresh"] as const) HEALTH[s] = HEALTH.dense;

const gate = (script: string, lines: GateLine[], exitCode = 0, stderr = ""): GateRun => ({
  ...run, script, lines, exitCode, stderr, stdout: "", error: exitCode !== 0,
});

const MIXED: GateRun[] = [
  gate("gate-figma.sh", [
    { type: "figma", id: "design-system", status: "changed", reason: "version 4120 → 4188" },
    { type: "figma", id: "icon-library", status: "not-checked", reason: "no credentials" },
  ]),
  gate("gate-github.sh", [
    { type: "github", id: "web", status: "changed", reason: "12 files changed in scope", delta: new Array(12) },
    { type: "github", id: "api", status: "unchanged", reason: "origin/main at 3f9c2e1" },
    { type: "github", id: "mobile", status: "not-checked", reason: "no clone" },
    { type: "github", id: "infra", status: "blocked", reason: "no into: set on this entry" },
  ]),
  gate("gate-website.sh", [
    { type: "website", id: "marketing-site", status: "unchanged", reason: "sitemap unchanged (148 pages)" },
    { type: "website", id: "docs", status: "changed", reason: "3 pages changed" },
  ]),
  gate("gate-monday.sh", [{ type: "monday", id: "roadmap", status: "never", reason: "no stored version" }]),
  gate("gate-ga.sh", [
    { type: "ga", id: "web-analytics", status: "unchanged", reason: "within lookback" },
    { type: "ga", id: "app-analytics", status: "not-checked", reason: "no credentials" },
    { type: "ga", id: "events", status: "unchanged", reason: "within lookback" },
  ]),
];

const OVERFLOW_GATES: GateRun[] = [
  gate("gate-github.sh", [
    { type: "github", id: "enterprise-partner-portal-frontend-monorepo", status: "not-checked",
      reason: "git fetch failed: ssh: connect to host github.com port 22: Operation timed out after 30 seconds (BatchMode=yes, no interactive auth)" },
  ]),
];

export const GATES: Partial<Record<StateName, GatesResponse>> = {
  "gates-mixed": { available: true, results: MIXED },
  dense: { available: true, results: MIXED },
  overflow: { available: true, results: OVERFLOW_GATES },
  "gate-error": {
    available: true,
    results: [MIXED[0], gate("gate-github.sh", [], 1, "✗ gate-github: python3 not found, so this source was not checked."), ...MIXED.slice(2)],
  },
  "first-run": { available: false, hint: "This brain has no sources.json yet; add a source with /add-source." },
};

/** Which states have run "Check sources now" already, so the comp opens with results showing. */
export const GATES_SHOWN: Partial<Record<StateName, boolean>> = { "gates-mixed": true, dense: true, overflow: true, "gate-error": true, "first-run": true };
