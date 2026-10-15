import { Dot } from "./bits";

export function ErrorNotice({ kind }: { kind: string }) {
  return (
    <div className="notice" role="alert">
      <Dot severity={kind === "unauthorized" ? "info" : "error"} />
      <div>
        <p className="notice-head">{kind === "unauthorized" ? "Open Studio from the link it printed." : "Studio's server isn't answering."}</p>
        <p className="notice-sub">
          {kind === "unauthorized"
            ? "This page needs the address Studio showed in your terminal when it started."
            : "It may have stopped. Check the terminal you started it from, or run npx brainforge-studio again."}
        </p>
      </div>
    </div>
  );
}
