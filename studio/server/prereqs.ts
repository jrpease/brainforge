// The setup screen's checks. v0 blocks only on what v0 needs; gh and claude come later.
import { spawnSync } from "node:child_process";

export type Prereq = { name: string; ok: boolean; detail: string; blocking: boolean; hint: string };

const run = (cmd: string, args: string[]) => {
  const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 10_000 });
  return { ok: r.status === 0 && !r.error, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim().split("\n")[0] ?? "" };
};

export function checkPrereqs(nodeVersion = process.versions.node): Prereq[] {
  const major = Number(nodeVersion.split(".")[0]);
  const git = run("git", ["--version"]);
  const py = run("python3", ["--version"]);
  const gh = run("gh", ["--version"]);
  const ghAuth = gh.ok ? run("gh", ["auth", "status"]) : { ok: false, out: "" };
  const claude = run("claude", ["--version"]);
  return [
    { name: "Node", ok: major >= 20, detail: `v${nodeVersion}`, blocking: true, hint: "Install Node 20 or later from nodejs.org." },
    { name: "git", ok: git.ok, detail: git.out, blocking: true, hint: "Install git from git-scm.com." },
    { name: "python3", ok: py.ok, detail: py.out, blocking: true, hint: "Install Python 3; the brain's source checks need it." },
    { name: "GitHub CLI", ok: gh.ok && ghAuth.ok, detail: gh.ok ? (ghAuth.ok ? "signed in" : "not signed in") : "", blocking: false, hint: gh.ok ? "Run gh auth login. Needed for later phases." : "Install gh from cli.github.com. Needed for later phases." },
    { name: "Claude Code", ok: claude.ok, detail: claude.out, blocking: false, hint: "Install Claude Code. Needed for later phases." },
  ];
}
