import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import { getCookie, setCookie } from "hono/cookie";
import { timingSafeEqual } from "node:crypto";
import type { BrainInfo } from "./brain.js";
import { checkPrereqs } from "./prereqs.js";
import { readContextFile } from "./readers/files.js";
import { readManifest } from "./readers/manifest.js";
import { readSources } from "./readers/sources.js";
import { canonHealth, gates, tripwires } from "./scripts.js";

const COOKIE = "studio_token";

const same = (a: string, b: string) => a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

export function createApp(opts: { brain: BrainInfo; token: string; clientDir?: string }) {
  const { brain, token, clientDir } = opts;
  const app = new Hono();

  // The URL Studio prints carries ?t=<token>; trade it for a cookie and drop it from the address bar.
  app.use("*", async (c, next) => {
    const t = c.req.query("t");
    if (t && same(t, token)) {
      setCookie(c, COOKIE, token, { httpOnly: true, sameSite: "Strict", path: "/" });
      const url = new URL(c.req.url);
      url.searchParams.delete("t");
      return c.redirect(url.pathname + url.search);
    }
    await next();
  });

  app.use("/api/*", async (c, next) => {
    const given = c.req.header("x-studio-token") ?? getCookie(c, COOKIE) ?? "";
    if (!same(given, token)) return c.json({ error: "unauthorized" }, 401);
    await next();
  });

  app.get("/api/brain", (c) => c.json(brain));
  app.get("/api/prereqs", (c) => c.json(checkPrereqs()));
  app.get("/api/health", async (c) => {
    const [canon, trips] = await Promise.all([canonHealth(brain.path), tripwires(brain.path)]);
    return c.json({ canon, tripwires: trips });
  });
  app.post("/api/gates/run", async (c) => c.json(await gates(brain.path)));
  app.get("/api/manifest", (c) => c.json(readManifest(brain.path)));
  app.get("/api/sources", (c) => c.json(readSources(brain.path)));
  app.get("/api/file", (c) => {
    const r = readContextFile(brain.path, c.req.query("path") ?? "");
    return r.ok ? c.text(r.text) : c.json({ error: r.status === 403 ? "outside context/" : "not found" }, r.status);
  });

  if (clientDir) {
    app.use("/*", serveStatic({ root: clientDir }));
    app.get("*", serveStatic({ root: clientDir, path: "index.html" }));
  }
  return app;
}
