// Builds a throwaway brain for a test, the way tests/canon-health.test.sh does: the scaffold's
// scripts, the synthetic acme-brain context, and synthetic sources and sync state, in a fresh git
// repo. A fresh `git init` matters: the fixture sits inside this repo, so a script that walks to
// the git root from it would land in brainforge/ instead.
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SCAFFOLD_SCRIPTS = join(REPO, "scaffold", ".brainforge");
const FIXTURE = join(REPO, "evals", "fixtures", "acme-brain");

export type BrainOptions = {
  /** synced: every source has synced; never: a source never synced; todo: a derived doc says source: TODO */
  sync?: "synced" | "never" | "todo";
  /** extra canon docs, each in its own state */
  canon?: Array<"stale" | "never-reviewed" | "stalled-draft">;
  /** stamp the drift watermark at HEAD (quiet), or leave none (the drift tripwire fires) */
  watermark?: boolean;
  /** leave files out, to stand in for an older or partial brain */
  omit?: Array<"tripwires" | "manifest" | "sources">;
};

export type Brain = { path: string; cleanup: () => void };

const day = 24 * 60 * 60 * 1000;
const isoDate = (msAgo: number) => new Date(Date.now() - msAgo).toISOString().slice(0, 10);

function git(cwd: string, args: string[], env: Record<string, string> = {}) {
  return execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...args], {
    cwd,
    env: { ...process.env, ...env },
    encoding: "utf8",
  });
}

function writeCanon(path: string, owner: string, lastReviewed: string, status: string) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `---\ntitle: T\nowner: ${owner}\nlast-reviewed: ${lastReviewed}\nstatus: ${status}\n---\n\n# T\nbody\n`);
}

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)],
  );
}

export function makeBrain(opts: BrainOptions = {}): Brain {
  const { sync = "synced", canon = [], watermark = true, omit = [] } = opts;
  const path = mkdtempSync(join(tmpdir(), "studio-brain-"));
  const bf = join(path, ".brainforge");
  mkdirSync(bf, { recursive: true });

  for (const f of readdirSync(SCAFFOLD_SCRIPTS).filter((f) => f.endsWith(".sh"))) {
    if (f === "tripwires.sh" && omit.includes("tripwires")) continue;
    cpSync(join(SCAFFOLD_SCRIPTS, f), join(bf, f));
    chmodSync(join(bf, f), 0o755);
  }
  cpSync(join(FIXTURE, "context"), join(path, "context"), { recursive: true });
  if (!omit.includes("manifest")) {
    cpSync(join(FIXTURE, ".brainforge", "brain-manifest.json"), join(bf, "brain-manifest.json"));
  }

  // The fixture's own review dates go stale on a calendar date; pin them to today.
  const today = isoDate(0);
  for (const f of walk(join(path, "context", "canon")).filter((f) => f.endsWith(".md"))) {
    const text = readFileSync(f, "utf8");
    if (/^last-reviewed:/m.test(text)) writeFileSync(f, text.replace(/^last-reviewed:.*$/m, `last-reviewed: ${today}`));
  }

  if (!omit.includes("sources")) {
    // One github entry with no localClone (gate says not-checked, no clone) and one figma entry
    // with no FIGMA_TOKEN in .env (gate says not-checked, no credentials).
    const sources = {
      version: 1,
      figma: [{ id: "design-system", fileKey: "FIXTUREKEY", extract: ["variables"], into: "context/derived/design-system/", enabled: true, cadence: "weekly" }],
      repos: [{ id: "web", remote: "github.com/acme/web", branch: "main", into: "context/derived/repos/", enabled: true, cadence: "weekly" }],
      websites: [],
      monday: [],
      ga: [],
    };
    writeFileSync(join(path, "sources.json"), JSON.stringify(sources, null, 2) + "\n");
    writeFileSync(join(path, ".env"), "# no credentials\n");
  }

  const synced = sync !== "never";
  const state = {
    version: 1,
    // Figma slots are keyed by fileKey and need a version (gate-figma.sh reads exactly that).
    figma: { FIXTUREKEY: synced ? { version: "1", lastModified: "2026-09-01T00:00:00Z", synced: true } : { synced: false } },
    repos: { web: synced ? { lastSha: "0000000000000000000000000000000000000000", synced: true } : { synced: false } },
    websites: {},
    monday: {},
    ga: {},
    lastFullSync: synced ? isoDate(7 * day) : null,
  };
  // JSON.stringify's two-space indent puts each slot's "synced" at six spaces, the file's contract.
  writeFileSync(join(path, ".sync-state.json"), JSON.stringify(state, null, 2) + "\n");
  if (sync === "todo") {
    const doc = join(path, "context", "derived", "repos", "todo.md");
    writeFileSync(doc, "---\nsource: TODO\n---\n\n# Unfilled\n");
  }

  if (canon.includes("stale")) writeCanon(join(path, "context/canon/brand/stale.md"), "Jordan", isoDate(400 * day), "approved");
  if (canon.includes("never-reviewed")) writeCanon(join(path, "context/canon/brand/never.md"), "TODO", "TODO", "approved");

  git(path, ["init", "-q"]);
  if (canon.includes("stalled-draft")) {
    // A draft is stalled by the age of its last commit, so it lands in a backdated first commit.
    writeCanon(join(path, "context/canon/brand/stalled.md"), "TODO", "TODO", "draft");
    const old = `${isoDate(200 * day)}T00:00:00`;
    git(path, ["add", "context/canon/brand/stalled.md"]);
    git(path, ["commit", "-q", "-m", "stalled draft"], { GIT_AUTHOR_DATE: old, GIT_COMMITTER_DATE: old });
  }
  git(path, ["add", "-A"]);
  git(path, ["commit", "-q", "-m", "brain"]);
  if (watermark) {
    writeFileSync(join(bf, "last-drift-review"), git(path, ["rev-parse", "HEAD"]));
    git(path, ["add", "-A"]);
    git(path, ["commit", "-q", "-m", "drift review"]);
  }

  return { path, cleanup: () => rmSync(path, { recursive: true, force: true }) };
}
