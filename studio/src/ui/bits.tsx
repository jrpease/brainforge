import { useState } from "react";
import type { Severity } from "../health/model";
import "./bits.css";

/** A command the admin runs in Claude Code. Click copies it. */
export function Command({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className={copied ? "cmd is-copied" : "cmd"}
      onClick={() => {
        navigator.clipboard?.writeText(text).catch(() => {});
        setCopied(true);
        setTimeout(() => setCopied(false), 1200);
      }}
      aria-label={`Copy ${text}`}
    >
      <span className="cmd-text">{text}</span>
      <span className="cmd-hint" aria-live="polite">{copied ? "copied" : "copy"}</span>
    </button>
  );
}

export function Dot({ severity }: { severity: Severity }) {
  return <span className={`dot dot-${severity}`} aria-hidden="true" />;
}

export function ThemeToggle({ theme, onTheme }: { theme: "dark" | "light"; onTheme: () => void }) {
  return (
    <button type="button" className="theme-toggle" onClick={onTheme} aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}>
      {theme === "dark" ? "Light" : "Dark"}
    </button>
  );
}

export function Skeleton({ w = "100%", h = 14 }: { w?: string | number; h?: number }) {
  return <span className="skel" style={{ width: w, height: h }} aria-hidden="true" />;
}
