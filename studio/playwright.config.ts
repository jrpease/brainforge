import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "test/smoke",
  timeout: 60_000,
  use: { headless: true },
  reporter: "list",
});
