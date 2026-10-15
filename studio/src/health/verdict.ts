// The one sentence at the top of Health, from what the scripts reported.
import type { Issue } from "./model";

export function verdict(issues: Issue[], current: number, isNew: boolean) {
  if (isNew) return { head: "This brain is new.", sub: "Canon is all drafts so far and no sources are connected. Run /forge to set it up." };
  const n = issues.length;
  if (n === 0) return { head: "Nothing needs you.", sub: `${current} canon ${current === 1 ? "doc is" : "docs are"} current.` };
  const stale = issues.filter((i) => i.title === "Past its review date").length;
  const never = issues.filter((i) => i.title === "Approved but never reviewed").length;
  const parts = [
    stale && `${stale} canon ${stale === 1 ? "doc is" : "docs are"} past review`,
    never && `${never} ${never === 1 ? "was" : "were"} never reviewed`,
    issues.some((i) => i.title.startsWith("Canon and synced")) && "canon may have drifted from synced facts",
    issues.some((i) => i.title === "A source has never synced") && "a source has never synced",
  ].filter(Boolean) as string[];
  const sub = parts.length > 1 ? `${parts.slice(0, -1).join(", ")} and ${parts.at(-1)}.` : `${parts[0]}.`;
  return { head: `${n} ${n === 1 ? "thing needs" : "things need"} you.`, sub: sub[0].toUpperCase() + sub.slice(1) };
}
