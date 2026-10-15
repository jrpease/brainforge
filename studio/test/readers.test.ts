import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { readManifest } from "../server/readers/manifest";
import { readSources } from "../server/readers/sources";
import { canonHealth, gates, runScript, tripwires } from "../server/scripts";
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

describe("slot keys", () => {
  it("finds monday and ga slots by boardId and propertyId, websites by id", () => {
    const b = brain();
    const src = JSON.parse(readFileSync(join(b.path, "sources.json"), "utf8"));
    src.monday = [{ id: "roadmap", boardId: 123, into: "context/derived/monday/" }];
    src.ga = [{ id: "web-analytics", propertyId: "456", into: "context/derived/ga/" }];
    src.websites = [{ id: "site", url: "https://x", into: "context/derived/web/" }];
    writeFileSync(join(b.path, "sources.json"), JSON.stringify(src));
    const st = JSON.parse(readFileSync(join(b.path, ".sync-state.json"), "utf8"));
    st.monday = { "123": { synced: true } };
    st.ga = { "456": { synced: true } };
    st.websites = { site: { synced: true } };
    writeFileSync(join(b.path, ".sync-state.json"), JSON.stringify(st));
    const r = readSources(b.path);
    if (!r.available) throw new Error("unavailable");
    for (const id of ["roadmap", "web-analytics", "site"]) {
      expect(r.entries.find((e) => e.entry.id === id)?.slot, id).toEqual({ synced: true });
    }
  });
});

describe("script timeouts", () => {
  it("kill the whole process group, not just bash", async () => {
    const b = brain();
    writeFileSync(join(b.path, ".brainforge", "slow.sh"), "sleep 30 &\nwait\n");
    const t0 = Date.now();
    const r = await runScript(b.path, "slow.sh", [], 500);
    expect(r.timedOut).toBe(true);
    expect(Date.now() - t0).toBeLessThan(5000);
  });
  it("gates say unavailable when .brainforge/ is missing", async () => {
    const b = brain();
    rmSync(join(b.path, ".brainforge"), { recursive: true });
    mkdirSync(join(b.path, "x"));
    expect(await gates(b.path)).toMatchObject({ available: false });
  });
});
