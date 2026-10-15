import { mkdtempSync, symlinkSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { checkPrereqs } from "../server/prereqs";

const PATH = process.env.PATH;
afterEach(() => {
  process.env.PATH = PATH;
});

const stubDir = (tools: Record<string, number>) => {
  const d = mkdtempSync(join(tmpdir(), "stub-bin-"));
  for (const [name, code] of Object.entries(tools)) {
    writeFileSync(join(d, name), `#!/bin/sh\necho "${name} stub"\nexit ${code}\n`);
    chmodSync(join(d, name), 0o755);
  }
  symlinkSync("/bin/sh", join(d, "sh"));
  return d;
};

describe("setup check", () => {
  it("names every missing tool, and blocks only on what v0 needs", () => {
    process.env.PATH = stubDir({});
    const r = Object.fromEntries(checkPrereqs("22.0.0").map((p) => [p.name, p]));
    expect(r.Node).toMatchObject({ ok: true, blocking: true });
    expect(r.git).toMatchObject({ ok: false, blocking: true });
    expect(r.python3).toMatchObject({ ok: false, blocking: true });
    expect(r["GitHub CLI"]).toMatchObject({ ok: false, blocking: false });
    expect(r["Claude Code"]).toMatchObject({ ok: false, blocking: false });
  });
  it("passes when everything is there and gh is signed in", () => {
    process.env.PATH = stubDir({ git: 0, python3: 0, gh: 0, claude: 0 });
    expect(checkPrereqs("20.11.0").every((p) => p.ok)).toBe(true);
  });
  it("flags gh installed but signed out, and Node below 20", () => {
    process.env.PATH = stubDir({ git: 0, python3: 0, claude: 0 });
    const d = process.env.PATH!;
    writeFileSync(join(d, "gh"), '#!/bin/sh\n[ "$1" = auth ] && exit 1\necho gh\n');
    chmodSync(join(d, "gh"), 0o755);
    const r = Object.fromEntries(checkPrereqs("18.19.0").map((p) => [p.name, p]));
    expect(r.Node.ok).toBe(false);
    expect(r["GitHub CLI"]).toMatchObject({ ok: false, detail: "not signed in" });
  });
});
