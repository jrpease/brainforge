import { readFileSync } from "node:fs";
import { join } from "node:path";

export function readManifest(brain: string) {
  try {
    return { available: true as const, manifest: JSON.parse(readFileSync(join(brain, ".brainforge", "brain-manifest.json"), "utf8")) };
  } catch {
    return { available: false as const, hint: "Not available in this brain; run /upgrade." };
  }
}
