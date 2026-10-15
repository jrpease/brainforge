import { spawnSync } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";
import { parseCanonReport } from "../src/lib/canonReport";
import { makeBrain, type Brain } from "./make-brain";

const made: Brain[] = [];
afterEach(() => made.splice(0).forEach((b) => b.cleanup()));
const report = (opts: Parameters<typeof makeBrain>[0]) => {
  const b = makeBrain(opts);
  made.push(b);
  return spawnSync("bash", [".brainforge/canon-health.sh"], { cwd: b.path, encoding: "utf8" }).stdout;
};

describe("parseCanonReport, against the real script", () => {
  it("reads every group and row the script prints", () => {
    const r = parseCanonReport(report({ canon: ["stale", "never-reviewed", "stalled-draft"] }));
    expect(r.parsed).toBe(true);
    if (!r.parsed) return;
    expect(r.counts).toMatchObject({ "past review": 1, "never reviewed": 1 });
    expect(r.groups["never-reviewed"]).toEqual([expect.objectContaining({ path: "context/canon/brand/never.md", owner: "TODO" })]);
    expect(r.groups["past-review"]).toEqual([expect.objectContaining({ path: "context/canon/brand/stale.md", owner: "Jordan" })]);
    expect(r.groups.drafts?.find((d) => d.path.endsWith("stalled.md"))?.stalled).toBe(true);
    expect(r.groups.drafts?.find((d) => d.path.endsWith("voice.md"))?.stalled).toBe(false);
    expect(r.footer.join(" ")).toContain("/approve-canon");
  });
  it("keeps a path longer than the script's 44-column pad apart from its date", () => {
    const text = `Canon health — context/canon
  0 approved and current · 1 past review · 0 never reviewed · 0 draft(s)

⚠ past review — the date someone last confirmed this is still true
    context/canon/brand/voice-and-tone-guidelines-for-marketing.md 2024-01-01  biannual (default)     owner: Priya
`;
    const r = parseCanonReport(text);
    expect(r.parsed).toBe(true);
    if (!r.parsed) return;
    expect(r.groups["past-review"]?.[0]).toMatchObject({ path: "context/canon/brand/voice-and-tone-guidelines-for-marketing.md", owner: "Priya" });
    expect(r.groups["past-review"]?.[0].detail).toBe("2024-01-01 · biannual (default)");
  });
  it("reads a clean report", () => {
    const r = parseCanonReport(report({}));
    expect(r.parsed).toBe(true);
    if (r.parsed) expect(r.groups["past-review"]).toBeUndefined();
  });
  it("falls back to raw text when the format is not the one it knows", () => {
    expect(parseCanonReport("something else\n")).toEqual({ parsed: false, text: "something else\n" });
  });
});
