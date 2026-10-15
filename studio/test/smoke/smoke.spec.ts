// The built CLI against a throwaway brain: Health and the Brain browser render, the console stays
// clean, and the API refuses a request without the launch token.
import { expect, test } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { makeBrain, type Brain } from "../make-brain";

const BIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "bin", "brainforge-studio.js");
let brain: Brain;
let server: ChildProcess;
let url: string;

test.beforeAll(async () => {
  brain = makeBrain({ canon: ["stale"], sync: "never", watermark: false });
  server = spawn(process.execPath, [BIN, brain.path, "--no-open"], { stdio: ["ignore", "pipe", "pipe"] });
  url = await new Promise<string>((done, fail) => {
    let out = "";
    server.stdout!.on("data", (d) => {
      out += d;
      const m = out.match(/http:\/\/127\.0\.0\.1:\d+\/\?t=[0-9a-f]+/);
      if (m) done(m[0]);
    });
    server.on("exit", (code) => fail(new Error(`studio exited ${code}: ${out}`)));
  });
});

test.afterAll(() => {
  server?.kill();
  brain?.cleanup();
});

test("Health and the Brain browser render with a clean console", async ({ page }) => {
  const problems: string[] = [];
  page.on("console", (m) => ["error", "warning"].includes(m.type()) && problems.push(m.text()));
  page.on("pageerror", (e) => problems.push(e.message));

  await page.goto(url);
  await expect(page.getByRole("heading", { level: 1 })).toContainText("need you");
  await expect(page.getByText("Past its review date")).toBeVisible();
  await expect(page.getByText("Canon and synced facts may have drifted")).toBeVisible();

  await page.getByRole("link", { name: "Brain" }).click();
  await expect(page.getByRole("heading", { name: "Brain", level: 1 })).toBeVisible();
  await page.locator(".br-file").first().click();
  await expect(page.locator(".br-body")).not.toBeEmpty();

  expect(problems).toEqual([]);
});

test("the API refuses a request without the launch token", async ({ request }) => {
  const res = await request.get(new URL("/api/health", url).href);
  expect(res.status()).toBe(401);
});
