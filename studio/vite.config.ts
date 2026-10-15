import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist/client", emptyOutDir: true },
  test: { include: ["test/**/*.test.ts"], testTimeout: 30000 },
});
