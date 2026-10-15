import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { makeBrain, type Brain } from "./make-brain";

const made: Brain[] = [];
const brain = (...args: Parameters<typeof makeBrain>) => {
  const b = makeBrain(...args);
  made.push(b);
  return b;
};
afterEach(() => made.splice(0).forEach((b) => b.cleanup()));

const run = (b: Brain, script: string, ...args: string[]) =>
  spawnSync("bash", [join(".brainforge", script), ...args], { cwd: b.path, encoding: "utf8" });

describe("makeBrain", () => {
  it("builds a quiet brain by default", () => {
    const b = brain();
    for (const f of ["sources.json", ".sync-state.json", ".brainforge/brain-manifest.json", ".brainforge/tripwires.sh", ".brainforge/canon-health.sh", ".brainforge/last-drift-review"]) {
      expect(existsSync(join(b.path, f)), f).toBe(true);
    }
    expect(run(b, "canon-health.sh").status).toBe(0);
    const tw = run(b, "tripwires.sh", b.path);
    expect(tw.status).toBe(0);
    expect(tw.stdout).toBe("");
  });

  it("makes stale canon that canon-health reports as a finding (exit 1)", () => {
    const b = brain({ canon: ["stale"] });
    const r = run(b, "canon-health.sh");
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("stale.md");
  });

  it("makes never-reviewed canon and a stalled draft", () => {
    const b = brain({ canon: ["never-reviewed", "stalled-draft"] });
    const r = run(b, "canon-health.sh");
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("never.md");
    expect(r.stdout).toContain("stalled.md");
  });

  it("trips the sync and drift tripwires", () => {
    const b = brain({ sync: "never", watermark: false });
    const r = run(b, "tripwires.sh", b.path);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("Sync health");
    expect(r.stdout).toContain("never had a drift review");
  });

  it("trips the sync tripwire on a TODO source", () => {
    const r = run(brain({ sync: "todo" }), "tripwires.sh");
    expect(r.stdout).toContain("Sync health");
  });

  it("can stand in for an older brain", () => {
    const b = brain({ omit: ["tripwires", "manifest", "sources"] });
    expect(existsSync(join(b.path, ".brainforge/tripwires.sh"))).toBe(false);
    expect(existsSync(join(b.path, ".brainforge/brain-manifest.json"))).toBe(false);
    expect(existsSync(join(b.path, "sources.json"))).toBe(false);
  });

  it("writes slots the gates read as not-checked", () => {
    const b = brain();
    const gh = run(b, "gate-github.sh");
    expect(gh.status).toBe(0);
    expect(JSON.parse(gh.stdout.trim().split("\n")[0]).status).toBe("not-checked");
    const fig = run(b, "gate-figma.sh");
    expect(fig.status).toBe(0);
    expect(JSON.parse(fig.stdout.trim().split("\n")[0])).toMatchObject({ status: "not-checked", reason: "no credentials" });
  });

  it("pins the fixture's canon review dates to today", () => {
    const b = brain();
    const text = readFileSync(join(b.path, "context/canon/company/org.md"), "utf8");
    expect(text).toContain(`last-reviewed: ${new Date().toISOString().slice(0, 10)}`);
  });
});
