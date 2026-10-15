// Reads canon-health.sh's full report into rows for display. Studio does not judge canon itself:
// every verdict here is a line the script printed. If the format ever stops matching, the caller
// shows the raw text instead (parsed: false).

export type CanonGroup = "never-reviewed" | "past-review" | "drafts";
export type CanonRow = { path: string; detail: string; owner?: string; stalled?: boolean };
export type CanonReport =
  | { parsed: true; summary: string; counts: Record<string, number>; groups: Partial<Record<CanonGroup, CanonRow[]>>; footer: string[] }
  | { parsed: false; text: string };

const HEADS: Array<[string, CanonGroup]> = [
  ["✗", "never-reviewed"],
  ["⚠", "past-review"],
  ["·", "drafts"],
];

export function parseCanonReport(text: string): CanonReport {
  const lines = text.split("\n");
  if (!/^Canon health/.test(lines[0] ?? "")) return { parsed: false, text };
  const summary = (lines[1] ?? "").trim();
  const counts: Record<string, number> = {};
  for (const part of summary.split("·")) {
    const m = part.trim().match(/^(\d+)\s+(.+)$/);
    if (m) counts[m[2].trim()] = Number(m[1]);
  }
  const groups: Partial<Record<CanonGroup, CanonRow[]>> = {};
  const footer: string[] = [];
  let current: CanonGroup | null = null;
  for (const raw of lines.slice(2)) {
    if (!raw.trim()) continue;
    const head = HEADS.find(([mark]) => raw.startsWith(mark + " "));
    if (head) {
      current = head[1];
      groups[current] = [];
      continue;
    }
    if (current && raw.startsWith("    ")) {
      // canon-health.sh pads the path to 44 columns, so a longer path is followed by a single space:
      // take the path as the first token, then split the rest on its two-space gaps.
      const line = raw.trim();
      const path = line.split(/\s/, 1)[0];
      const cells = [path, ...line.slice(path.length).trim().split(/\s{2,}/).filter(Boolean)];
      const owner = cells.find((c) => c.startsWith("owner:"))?.slice(6).trim();
      const rest = cells.slice(1).filter((c) => !c.startsWith("owner:"));
      const detail = rest.join(" · ");
      groups[current]!.push({ path: cells[0], detail, owner, stalled: current === "drafts" ? /stalled$/.test(detail) : undefined });
      continue;
    }
    current = null;
    footer.push(raw.trim());
  }
  return { parsed: true, summary, counts, groups, footer };
}
