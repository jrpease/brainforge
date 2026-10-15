import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "../../src/styles/fonts.css";
import "../../src/styles/tokens.css";
import "../../src/styles/tokens.draft.css";
import "../../src/styles/base.css";
import { BRAIN, STATES, type StateName } from "./fixtures";
import { HealthLedger } from "./a-ledger/HealthLedger";
import { HealthSeam } from "./b-seam/HealthSeam";
import { useHealth } from "./useHealth";
import "./comps.css";

// URL drives everything so the state harness can shoot each cell:
//   ?dir=a|b&state=<name>&theme=dark|light&chrome=0
const q = new URLSearchParams(location.search);
if (q.get("still") === "1") document.documentElement.dataset.still = "";

function App() {
  const [dir, setDir] = useState(q.get("dir") === "b" ? "b" : "a");
  const [state, setState] = useState<StateName>((STATES as readonly string[]).includes(q.get("state") ?? "") ? (q.get("state") as StateName) : "dense");
  const [theme, setTheme] = useState(q.get("theme") === "light" ? "light" : "dark");
  const showPicker = q.get("chrome") !== "0";
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);
  const model = useHealth(state, true);
  const View = dir === "a" ? HealthLedger : HealthSeam;
  return (
    <>
      {showPicker && (
        <div className="comp-picker" role="toolbar" aria-label="Comp controls">
          <select aria-label="Direction" value={dir} onChange={(e) => setDir(e.target.value)}>
            <option value="a">A · Ledger</option>
            <option value="b">B · Seam</option>
          </select>
          <select aria-label="State" value={state} onChange={(e) => setState(e.target.value as StateName)}>
            {STATES.map((s) => <option key={s}>{s}</option>)}
          </select>
          <button type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>{theme}</button>
        </div>
      )}
      <View brain={BRAIN} model={model} theme={theme as "dark" | "light"} onTheme={() => setTheme(theme === "dark" ? "light" : "dark")} />
    </>
  );
}

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
