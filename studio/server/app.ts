import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import { timingSafeEqual } from "node:crypto";
import type { BrainInfo } from "./brain.js";
import { checkPrereqs } from "./prereqs.js";
import { readContextFile } from "./readers/files.js";
import { readManifest } from "./readers/manifest.js";
import { readSources } from "./readers/sources.js";
import { canonHealth, gates, tripwires } from "./scripts.js";

// Byte length, not string length: a multibyte character would make timingSafeEqual throw.
const same = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export function createApp(opts: { brain: BrainInfo; token: string; clientDir?: string }) {
  const { brain, token, clientDir } = opts;
  const app = new Hono();

  // The token travels only as a header the page adds itself, never as a cookie: cookies are not
  // port-isolated, so any other server on 127.0.0.1 would receive one, and a page on another local
  // port could send it. A custom header from another origin needs a CORS preflight, which this
  // server never grants.
  app.use("/api/*", async (c, next) => {
    const given = c.req.header("x-studio-token") ?? "";
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
