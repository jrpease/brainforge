// Turns the API's script output into what Health shows. Every verdict is the script's; this only
// sorts and labels it, and names the command that acts on it.
import { parseCanonReport, type CanonRow } from "../lib/canonReport";
import type { GateLine, GatesResponse, HealthResponse } from "../lib/types";

export type Severity = "stale" | "warning" | "error" | "info" | "ok";
export type Issue = { key: string; severity: Severity; title: string; path?: string; meta: string[]; command?: string };

const doc = (path: string) => path.replace(/^context\/canon\//, "").replace(/\.md$/, "");

export function canonView(h: HealthResponse | undefined) {
  const c = h?.canon;
  if (!c) return { kind: "none" as const };
  if (!c.available) return { kind: "unavailable" as const, hint: c.hint };
  if (c.error) return { kind: "error" as const, detail: (c.stderr || c.stdout).trim() || `exited ${c.exitCode}` };
  const r = parseCanonReport(c.stdout);
  if (!r.parsed) return { kind: "raw" as const, text: r.text };
  const issues: Issue[] = [
    ...(r.groups["never-reviewed"] ?? []).map((row) => issue(row, "stale", "Approved but never reviewed")),
    ...(r.groups["past-review"] ?? []).map((row) => issue(row, "stale", "Past its review date")),
  ];
  const drafts = r.groups.drafts ?? [];
  return {
    kind: "ok" as const,
    issues,
    stalled: drafts.filter((d) => d.stalled),
    open: drafts.filter((d) => !d.stalled),
    current: r.counts["approved and current"] ?? 0,
    summary: r.summary,
    footer: r.footer,
  };
}

function issue(row: CanonRow, severity: Severity, title: string): Issue {
  const meta = row.detail ? row.detail.split(" · ").filter(Boolean) : [];
  if (row.owner) meta.push(row.owner === "TODO" ? "no owner" : `owner ${row.owner}`);
  return { key: row.path, severity, title, path: row.path, meta, command: `/approve-canon ${doc(row.path)}` };
}

export function nudges(h: HealthResponse | undefined) {
  const t = h?.tripwires;
  if (!t) return { kind: "none" as const };
  if (!t.available) return { kind: "unavailable" as const, hint: t.hint };
  if (t.error) return { kind: "error" as const, detail: t.stderr.trim() || `exited ${t.exitCode}` };
  const items: Issue[] = t.lines.map((line) => {
    const text = line.replace(/^⚠️\s*/, "");
    const command = text.match(/run (\/[a-z-]+)/)?.[1];
    const isDrift = /drift/i.test(text);
    return {
      key: line,
      severity: isDrift ? "stale" : "warning",
      title: isDrift ? "Canon and synced facts may have drifted" : "A source has never synced",
      meta: [text.replace(/\s*—\s*run \/[a-z-]+.*$/, "").replace(/^Sync health:\s*/, "").replace(/^\w/, (c) => c.toUpperCase())],
      command,
    };
  });
  return { kind: "ok" as const, items };
}

export type SourceRow = { key: string; type: string; id: string; status: string; reason: string; severity: Severity; command?: string };

const STATUS: Record<string, { label: string; severity: Severity }> = {
  changed: { label: "Changed upstream", severity: "stale" },
  never: { label: "Never synced", severity: "warning" },
  unchanged: { label: "Up to date", severity: "ok" },
  "not-checked": { label: "Not checked", severity: "info" },
  blocked: { label: "Blocked", severity: "warning" },
};

export function sourceRows(g: GatesResponse): { rows: SourceRow[]; broken: { script: string; detail: string }[] } {
  if (!g.available) return { rows: [], broken: [] };
  const rows: SourceRow[] = [];
  const broken: { script: string; detail: string }[] = [];
  for (const r of g.results) {
    if (r.error) broken.push({ script: r.script, detail: (r.stderr || r.stdout).trim() || (r.timedOut ? "timed out" : `exited ${r.exitCode}`) });
    for (const l of r.lines as GateLine[]) {
      const s = STATUS[l.status ?? ""] ?? { label: l.status ?? "unknown", severity: "info" as Severity };
      rows.push({
        key: `${l.type}:${l.id}`,
        type: l.type ?? r.script.replace(/^gate-|\.sh$/g, ""),
        id: l.id ?? "?",
        status: s.label,
        reason: l.reason ?? "",
        severity: s.severity,
        command: l.status === "changed" || l.status === "never" ? `/sync ${l.id}` : undefined,
      });
    }
  }
  const rank: Record<Severity, number> = { stale: 0, error: 1, warning: 2, info: 3, ok: 4 };
  rows.sort((a, b) => rank[a.severity] - rank[b.severity]);
  return { rows, broken };
}
