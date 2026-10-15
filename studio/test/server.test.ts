import { execFileSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../server/app";
import { findBrain } from "../server/brain";
import { parseArgs, start } from "../server/cli";
import { makeBrain, type Brain } from "./make-brain";

const made: Brain[] = [];
const brain = (...a: Parameters<typeof makeBrain>) => {
  const b = makeBrain(...a);
  made.push(b);
  return b;
};
afterEach(() => made.splice(0).forEach((b) => b.cleanup()));

const TOKEN = "t".repeat(64);
const appFor = (b: Brain) => createApp({ brain: { path: b.path, name: "acme" }, token: TOKEN });
const authed = { headers: { "x-studio-token": TOKEN } };

describe("finding the brain", () => {
  it("refuses a folder that is not a brain", () => {
    const empty = mkdtempSync(join(tmpdir(), "not-a-brain-"));
    const r = findBrain(empty, "/");
    expect("error" in r && r.error).toMatch(/not a Brainforge brain/);
  });
  it("accepts a brain, by path or by cwd", () => {
    const b = brain();
    expect(findBrain(b.path, "/")).toMatchObject({ path: b.path });
    expect(findBrain(undefined, b.path)).toMatchObject({ path: b.path });
  });
});

describe("arguments", () => {
  it("parses path, --port and --no-open", () => {
    expect(parseArgs(["/x", "--port", "4000", "--no-open"], {})).toEqual({ path: "/x", port: 4000, open: false });
  });
  it("honours BRAINFORGE_STUDIO_NO_OPEN=1", () => {
    expect(parseArgs([], { BRAINFORGE_STUDIO_NO_OPEN: "1" })).toMatchObject({ open: false });
  });
  it("rejects junk", () => {
    expect(parseArgs(["--port", "nope"], {})).toHaveProperty("error");
    expect(parseArgs(["a", "b"], {})).toHaveProperty("error");
  });
});

describe("the locked-down API", () => {
  it("refuses /api without the token", async () => {
    const app = appFor(brain());
    expect((await app.request("/api/brain")).status).toBe(401);
    expect((await app.request("/api/brain", { headers: { "x-studio-token": "wrong" } })).status).toBe(401);
    expect((await app.request("/api/brain", authed)).status).toBe(200);
  });
  it("never sets a cookie, and a cookie alone is not accepted", async () => {
    const app = appFor(brain());
    const page = await app.request(`/?t=${TOKEN}`);
    expect(page.headers.get("set-cookie")).toBeNull();
    const withCookie = await app.request("/api/brain", { headers: { cookie: `studio_token=${TOKEN}` } });
    expect(withCookie.status).toBe(401);
  });
  it("answers 401, not 500, to a token with multibyte characters", async () => {
    const app = appFor(brain());
    const r = await app.request("/api/brain", { headers: { "x-studio-token": "é".repeat(64) } });
    expect(r.status).toBe(401);
  });
  it("sends no CORS headers, so another origin cannot read or preflight", async () => {
    const app = appFor(brain());
    const r = await app.request("/api/health", { method: "OPTIONS", headers: { origin: "http://127.0.0.1:5173", "access-control-request-method": "POST", "access-control-request-headers": "x-studio-token" } });
    expect(r.headers.get("access-control-allow-origin")).toBeNull();
  });
  it("will not read files outside context/", async () => {
    const app = appFor(brain());
    expect((await app.request("/api/file?path=context/canon/company/org.md", authed)).status).toBe(200);
    expect((await app.request("/api/file?path=sources.json", authed)).status).toBe(403);
    expect((await app.request("/api/file?path=context/../.env", authed)).status).toBe(403);
    expect((await app.request("/api/file?path=context/canon", authed)).status).toBe(404);
    expect((await app.request("/api/file?path=context", authed)).status).toBe(403);
  });
});

describe("the real server", () => {
  it("listens on 127.0.0.1 and never writes to the brain", async () => {
    const b = brain({ canon: ["stale"], sync: "never" });
    const before = execFileSync("git", ["status", "--porcelain"], { cwd: b.path, encoding: "utf8" });
    const { url, close } = await start({ brainPath: b.path, port: 0 });
    try {
      expect(url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/\?t=[0-9a-f]{64}$/);
      const base = new URL(url);
      const headers = { "x-studio-token": base.searchParams.get("t")! };
      for (const [path, method] of [["/api/health", "GET"], ["/api/gates/run", "POST"], ["/api/manifest", "GET"], ["/api/sources", "GET"]] as const) {
        expect((await fetch(new URL(path, base), { method, headers })).status, path).toBe(200);
      }
    } finally {
      close();
    }
    const after = execFileSync("git", ["status", "--porcelain"], { cwd: b.path, encoding: "utf8" });
    expect(after).toBe(before);
  });
});
