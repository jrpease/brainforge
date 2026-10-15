// The Sources list: sources.json entries beside their .sync-state.json slots, shown as-is.
// No fresh/stale verdict here; that is /sync-health's job (row "Health: what v0 shows").
import { readFileSync } from "node:fs";
import { join } from "node:path";

type Json = Record<string, unknown>;
const read = (p: string): Json | null => {
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch {
    return null;
  }
};

// sources.json key → adapter type, as the gates and envelope-check name them
const TYPE: Record<string, string> = { repos: "github", websites: "website" };

export function readSources(brain: string) {
  const sources = read(join(brain, "sources.json"));
  if (!sources) return { available: false as const, hint: "This brain has no sources.json yet; add a source with /add-source." };
  const state = read(join(brain, ".sync-state.json")) ?? {};
  const entries = [];
  for (const [key, list] of Object.entries(sources)) {
    if (key.startsWith("$") || !Array.isArray(list)) continue;
    const slots = (state[key] ?? {}) as Json;
    for (const e of list as Json[]) {
      const slotKey = key === "figma" ? (e.fileKey as string) : (e.id as string);
      entries.push({ key, type: TYPE[key] ?? key, entry: e, slot: (slots[slotKey] as Json) ?? null });
    }
  }
  return { available: true as const, lastFullSync: state.lastFullSync ?? null, entries };
}
