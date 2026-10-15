import { useEffect, useState } from "react";
import { ApiError, getJson } from "./api";
import { BrainScreen } from "./brain/BrainScreen";
import { HealthScreen } from "./health/HealthScreen";
import { useHealth } from "./health/useHealth";
import type { BrainInfo } from "./lib/types";
import { SetupScreen, type Prereq } from "./setup/SetupScreen";
import { SourcesScreen } from "./sources/SourcesScreen";
import { currentTheme, setTheme, type Theme } from "./theme";
import { ThemeToggle } from "./ui/bits";
import "./app.css";

type Screen = "health" | "brain" | "sources" | "setup";
const SCREENS: Screen[] = ["health", "brain", "sources", "setup"];
const fromHash = (): Screen => {
  const h = location.hash.slice(1) as Screen;
  return SCREENS.includes(h) ? h : "health";
};

export function App() {
  const [screen, setScreen] = useState<Screen>(fromHash);
  const [theme, setThemeState] = useState<Theme>(currentTheme);
  const [brain, setBrain] = useState<BrainInfo>();
  const [prereqs, setPrereqs] = useState<Prereq[]>();
  const health = useHealth();

  useEffect(() => {
    const on = () => setScreen(fromHash());
    window.addEventListener("hashchange", on);
    getJson<BrainInfo>("/api/brain").then(setBrain).catch(() => {});
    getJson<Prereq[]>("/api/prereqs").then(setPrereqs).catch((e) => e instanceof ApiError || setPrereqs([]));
    return () => window.removeEventListener("hashchange", on);
  }, []);

  const blocked = prereqs?.some((p) => p.blocking && !p.ok);
  const missing = prereqs?.some((p) => !p.ok);
  const shown: Screen = blocked ? "setup" : screen;
  const nav: Array<[Screen, string]> = [["health", "Health"], ["brain", "Brain"], ["sources", "Sources"]];
  if (missing) nav.push(["setup", "Setup"]);

  return (
    <div className="app">
      <header className="bar">
        <div className="bar-mark">Brainforge <em>Studio</em></div>
        <nav className="bar-nav" aria-label="Screens">
          {nav.map(([id, label]) => (
            <a key={id} href={`#${id}`} aria-current={shown === id ? "page" : undefined}>
              {label}
              {id === "setup" && <span className={`dot ${blocked ? "dot-error" : "dot-warning"}`} aria-label="needs attention" />}
            </a>
          ))}
        </nav>
        {brain && (
          <div className="bar-brain" title={brain.path}>
            <span className="bar-brain-name">{brain.name}</span> <span className="bar-brain-path">{brain.path}</span>
          </div>
        )}
        <ThemeToggle
          theme={theme}
          onTheme={() => {
            const next = theme === "dark" ? "light" : "dark";
            setTheme(next);
            setThemeState(next);
          }}
        />
      </header>
      <main className="main">
        {shown === "setup" && <SetupScreen prereqs={prereqs ?? []} blocked={!!blocked} />}
        {shown === "health" && <HealthScreen model={health} />}
        {shown === "brain" && <BrainScreen />}
        {shown === "sources" && <SourcesScreen />}
      </main>
    </div>
  );
}
