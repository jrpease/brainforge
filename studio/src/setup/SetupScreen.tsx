import { Dot } from "../ui/bits";

export type Prereq = { name: string; ok: boolean; detail: string; blocking: boolean; hint: string };

export function SetupScreen({ prereqs, blocked }: { prereqs: Prereq[]; blocked: boolean }) {
  return (
    <section aria-label="Setup">
      <div className="screen-head">
        <h1>{blocked ? "Studio needs a few things first." : "Setup"}</h1>
        <p>
          {blocked
            ? "Studio runs the brain's own scripts on this computer, so it needs the tools they use. Install what's missing, then reload this page."
            : "Everything Studio needs today is here. The rest is for later phases."}
        </p>
      </div>
      <div className="rows">
        {prereqs.map((p) => (
          <div className="row" key={p.name}>
            <Dot severity={p.ok ? "ok" : p.blocking ? "error" : "warning"} />
            <div className="row-main">
              <div className="row-title">{p.name} <span className="row-status">{p.ok ? "Ready" : p.blocking ? "Required" : "Needed later"}</span></div>
              <div className="row-meta">{p.ok ? p.detail || "found" : p.hint}</div>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
