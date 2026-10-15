import { serve } from "@hono/node-server";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import type { AddressInfo } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "./app.js";
import { findBrain } from "./brain.js";

const USAGE = "usage: brainforge-studio [brain-path] [--port <n>] [--no-open]";

export type Args = { path?: string; port: number; open: boolean } | { error: string };

export function parseArgs(argv: string[], env: NodeJS.ProcessEnv = process.env): Args {
  let path: string | undefined;
  let port = 0;
  let open = env.BRAINFORGE_STUDIO_NO_OPEN !== "1";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--no-open") open = false;
    else if (a === "--port") {
      port = Number(argv[++i]);
      if (!Number.isInteger(port) || port < 0 || port > 65535) return { error: USAGE };
    } else if (a === "-h" || a === "--help") return { error: USAGE };
    else if (a.startsWith("-") || path) return { error: USAGE };
    else path = a;
  }
  return { path, port, open };
}

export function start(opts: { brainPath: string; port: number; clientDir?: string }) {
  const brain = findBrain(opts.brainPath, process.cwd());
  if ("error" in brain) throw new Error(brain.error);
  const token = randomBytes(32).toString("hex");
  const app = createApp({ brain, token, clientDir: opts.clientDir });
  return new Promise<{ url: string; close: () => void }>((done) => {
    const server = serve({ fetch: app.fetch, hostname: "127.0.0.1", port: opts.port }, (info: AddressInfo) => {
      done({ url: `http://127.0.0.1:${info.port}/?t=${token}`, close: () => server.close() });
    });
  });
}

function openBrowser(url: string) {
  const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "cmd" : "xdg-open";
  const args = process.platform === "win32" ? ["/c", "start", "", url] : [url];
  spawn(cmd, args, { stdio: "ignore", detached: true }).on("error", () => {}).unref();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if ("error" in args) {
    console.error(args.error);
    process.exit(1);
  }
  const brain = findBrain(args.path, process.cwd());
  if ("error" in brain) {
    console.error(brain.error);
    process.exit(1);
  }
  const clientDir = join(dirname(fileURLToPath(import.meta.url)), "..", "client");
  const { url } = await start({ brainPath: brain.path, port: args.port, clientDir });
  console.log(`Brainforge Studio for ${brain.name}\n${url}`);
  if (args.open) openBrowser(url);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
