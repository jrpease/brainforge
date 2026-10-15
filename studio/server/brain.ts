import { existsSync, statSync } from "node:fs";
import { basename, resolve } from "node:path";

export type BrainInfo = { path: string; name: string };

/** A brain is a folder with a sources.json or a .brainforge/ (row "Finding the brain"). */
export function findBrain(arg: string | undefined, cwd: string): BrainInfo | { error: string } {
  const path = resolve(cwd, arg ?? ".");
  if (!existsSync(path) || !statSync(path).isDirectory()) return { error: `${path} is not a folder.` };
  if (!existsSync(resolve(path, "sources.json")) && !existsSync(resolve(path, ".brainforge"))) {
    return { error: `${path} is not a Brainforge brain (no sources.json and no .brainforge/). Run brainforge-studio inside a brain, or pass its path.` };
  }
  return { path, name: basename(path) };
}
