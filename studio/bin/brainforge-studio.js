#!/usr/bin/env node
import { pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const cli = join(dirname(fileURLToPath(import.meta.url)), "..", "dist", "server", "cli.js");
process.argv[1] = cli;
await import(pathToFileURL(cli).href);
