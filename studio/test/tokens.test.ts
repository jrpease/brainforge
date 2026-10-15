// Every semantic token resolves to a primitive, in both modes; nothing points at a name that
// does not exist.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(import.meta.dirname, "..", "src", "styles", "tokens.draft.css"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const block = (selector: string) => {
  const i = css.indexOf(`${selector} {`);
  return css.slice(i, css.indexOf("}", i));
};
const decls = (b: string) => Object.fromEntries([...b.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));

const root = decls(block(":root"));
const light = decls(block('[data-theme="light"]'));
const isPrimitive = (name: string) => name in root && !root[name].startsWith("var(");

describe("draft tokens", () => {
  for (const [mode, set] of [["dark", root], ["light", light]] as const) {
    it(`every semantic colour resolves to a primitive in ${mode}`, () => {
      const semantic = Object.entries(set).filter(([, v]) => v.startsWith("var("));
      expect(semantic.length).toBeGreaterThan(10);
      for (const [name, v] of semantic) {
        const target = v.match(/^var\((--[\w-]+)\)$/)?.[1];
        expect(target && isPrimitive(target), `${name}: ${v}`).toBe(true);
      }
    });
  }
  it("light overrides every semantic colour dark defines", () => {
    const darkSemantic = Object.keys(root).filter((k) => root[k].startsWith("var(--color"));
    expect(Object.keys(light).filter((k) => k.startsWith("--color")).sort()).toEqual(darkSemantic.sort());
  });
});
