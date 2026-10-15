// Runs the brain's own scripts and reports what they say. Studio never recomputes their
// verdicts, and never adds to their environment: the gates read the brain's .env themselves.
import { spawn } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

export type Unavailable = { available: false; hint: string };
export type ScriptResult = { available: true; exitCode: number | null; stdout: string; stderr: string; timedOut: boolean };

const UPGRADE: Unavailable = { available: false, hint: "Not available in this brain; run /upgrade." };

export function runScript(brain: string, script: string, args: string[], timeoutMs: number): Promise<ScriptResult> {
  return new Promise((done) => {
    // detached: the script leads its own process group, so a timeout kills python3/curl/git with it
    // instead of leaving them holding the pipe open long after "timed out".
    const child = spawn("bash", [join(".brainforge", script), ...args], { cwd: brain, stdio: ["ignore", "pipe", "pipe"], detached: true });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        process.kill(-child.pid!, "SIGKILL");
      } catch {
        child.kill("SIGKILL");
      }
    }, timeoutMs);
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("close", (code) => {
      clearTimeout(timer);
      done({ available: true, exitCode: code, stdout, stderr, timedOut });
    });
    child.on("error", (e) => {
      clearTimeout(timer);
      done({ available: true, exitCode: null, stdout, stderr: stderr + String(e), timedOut });
    });
  });
}

const has = (brain: string, script: string) => existsSync(join(brain, ".brainforge", script));

/** canon-health.sh, full report. Exit 1 is a finding (stale canon), not an error. */
export async function canonHealth(brain: string) {
  if (!has(brain, "canon-health.sh")) return UPGRADE;
  const r = await runScript(brain, "canon-health.sh", [], 20_000);
  return { ...r, finding: r.exitCode === 1, error: r.timedOut || (r.exitCode !== 0 && r.exitCode !== 1) };
}

/** tripwires.sh. Always exits 0; anything else means the script broke. */
export async function tripwires(brain: string) {
  if (!has(brain, "tripwires.sh")) return UPGRADE;
  const r = await runScript(brain, "tripwires.sh", [brain], 10_000);
  const lines = r.stdout.split("\n").filter((l) => l.trim());
  return { ...r, lines, error: r.timedOut || r.exitCode !== 0 };
}

export type GateLine = { type?: string; id?: string; status?: string; reason?: string; [k: string]: unknown };

/** Every gate-*.sh, on demand. Exit 1 means misuse or no python3: an error, never a finding. */
export async function gates(brain: string) {
  if (!existsSync(join(brain, "sources.json"))) {
    return { available: false as const, hint: "This brain has no sources.json yet; add a source with /add-source." };
  }
  if (!existsSync(join(brain, ".brainforge"))) return UPGRADE;
  const scripts = readdirSync(join(brain, ".brainforge")).filter((f) => /^gate-[a-z]+\.sh$/.test(f)).sort();
  const results = await Promise.all(
    scripts.map(async (script) => {
      const r = await runScript(brain, script, [], 60_000);
      const lines: GateLine[] = [];
      for (const l of r.stdout.split("\n").filter((l) => l.trim())) {
        try {
          lines.push(JSON.parse(l));
        } catch {
          lines.push({ status: "unparsed", reason: l });
        }
      }
      return { script, ...r, lines, error: r.timedOut || r.exitCode !== 0 };
    }),
  );
  return { available: true as const, results };
}
