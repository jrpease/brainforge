import { afterEach, describe, expect, it } from "vitest";
import { readManifest } from "../server/readers/manifest";
import { readSources } from "../server/readers/sources";
import { canonHealth, gates, tripwires } from "../server/scripts";
import { makeBrain, type Brain } from "./make-brain";

const made: Brain[] = [];
const brain = (...a: Parameters<typeof makeBrain>) => {
  const b = makeBrain(...a);
  made.push(b);
  return b;
};
afterEach(() => made.splice(0).forEach((b) => b.cleanup()));

describe("canon health", () => {
  it("reports stale canon as a finding, not an error", async () => {
    const r = await canonHealth(brain({ canon: ["stale"] }).path);
    expect(r).toMatchObject({ available: true, exitCode: 1, finding: true, error: false });
  });
  it("is clean on a fresh brain", async () => {
    expect(await canonHealth(brain().path)).toMatchObject({ exitCode: 0, finding: false, error: false });
  });
});

describe("tripwires", () => {
  it("passes the lines through on a tripped brain", async () => {
    const r = await tripwires(brain({ sync: "never", watermark: false }).path);
    expect(r.available).toBe(true);
    if (!r.available) return;
    expect(r.error).toBe(false);
    expect(r.lines.some((l) => l.includes("Sync health"))).toBe(true);
    expect(r.lines.some((l) => l.includes("drift review"))).toBe(true);
  });
  it("is unavailable, not broken, on a brain without tripwires.sh", async () => {
    const b = brain({ omit: ["tripwires"] });
    expect(await tripwires(b.path)).toMatchObject({ available: false });
    expect(await canonHealth(b.path)).toMatchObject({ available: true });
  });
});

describe("gates", () => {
  it("shows each gate's own not-checked line", async () => {
    const r = await gates(brain().path);
    expect(r.available).toBe(true);
    if (!r.available) return;
    const lines = r.results.flatMap((g) => g.lines);
    expect(lines).toContainEqual(expect.objectContaining({ type: "figma", status: "not-checked", reason: "no credentials" }));
    expect(lines).toContainEqual(expect.objectContaining({ type: "github", id: "web", status: "not-checked" }));
    expect(r.results.every((g) => !g.error)).toBe(true);
  });
  it("is unavailable without sources.json", async () => {
    expect(await gates(brain({ omit: ["sources"] }).path)).toMatchObject({ available: false });
  });
});

describe("readers", () => {
  it("reads the manifest, or says it is missing", () => {
    expect(readManifest(brain().path)).toMatchObject({ available: true });
    expect(readManifest(brain({ omit: ["manifest"] }).path)).toMatchObject({ available: false });
  });
  it("lists sources with their sync slots as-is", () => {
    const r = readSources(brain({ sync: "never" }).path);
    expect(r.available).toBe(true);
    if (!r.available) return;
    expect(r.lastFullSync).toBeNull();
    expect(r.entries).toContainEqual(expect.objectContaining({ type: "github", slot: { synced: false } }));
    expect(r.entries).toContainEqual(expect.objectContaining({ type: "figma", slot: { synced: false } }));
  });
});
