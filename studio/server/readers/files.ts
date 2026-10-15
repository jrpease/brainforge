import { readFileSync, realpathSync } from "node:fs";
import { join, relative, sep } from "node:path";

/** Reads one file under the brain's context/, refusing anything that resolves outside it. */
export function readContextFile(brain: string, rel: string) {
  const root = realpathSync(join(brain, "context"));
  let path: string;
  try {
    path = realpathSync(join(brain, rel));
  } catch {
    return { ok: false as const, status: 404 as const };
  }
  const r = relative(root, path);
  if (r.startsWith("..") || r.split(sep)[0] === ".." || path === root) return { ok: false as const, status: 403 as const };
  return { ok: true as const, text: readFileSync(path, "utf8") };
}
