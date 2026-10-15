import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles/fonts.css";
import "./styles/tokens.css";
import "./styles/tokens.draft.css";
import { initTheme } from "./theme";

initTheme();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <main>Brainforge Studio</main>
  </StrictMode>,
);
