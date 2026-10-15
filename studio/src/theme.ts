// The theme switch (Studio owns it; design-system spec, "Modes"). Dark is the bare :root, light
// is [data-theme="light"]. A stored choice wins; otherwise follow the system setting.
export type Theme = "dark" | "light";
const KEY = "brainforge-studio-theme";

function stored(): Theme | null {
  try {
    const v = localStorage.getItem(KEY);
    return v === "dark" || v === "light" ? v : null;
  } catch {
    return null;
  }
}

const system = (): Theme => (window.matchMedia?.("(prefers-color-scheme: light)").matches ? "light" : "dark");

export function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
}

export function currentTheme(): Theme {
  return stored() ?? system();
}

/** Call once at startup: apply the theme, and follow the system while nothing is stored. */
export function initTheme() {
  applyTheme(currentTheme());
  window.matchMedia?.("(prefers-color-scheme: light)").addEventListener("change", () => {
    if (!stored()) applyTheme(system());
  });
}

export function setTheme(theme: Theme) {
  try {
    localStorage.setItem(KEY, theme);
  } catch {
    // storage blocked: the choice lasts for this page only
  }
  applyTheme(theme);
}
