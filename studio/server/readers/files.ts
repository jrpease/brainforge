import { readFileSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, join, relative, sep } from "node:path";

/** Reads one file under the brain's context/, refusing anything that resolves outside it. */
export function readContextFile(brain: string, rel: string) {
  let root: string;
  let path: string;
  try {
    root = realpathSync(join(brain, "context"));
    path = realpathSync(join(brain, rel));
  } catch {
    return { ok: false as const, status: 404 as const };
  }
  const r = relative(root, path);
  if (r === "" || r === ".." || r.startsWith(".." + sep) || isAbsolute(r)) return { ok: false as const, status: 403 as const };
  if (!statSync(path).isFile()) return { ok: false as const, status: 404 as const };
  return { ok: true as const, text: readFileSync(path, "utf8") };
}
