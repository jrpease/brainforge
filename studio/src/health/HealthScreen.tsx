import { canonView, nudges, sourceRows, type Issue, type SourceRow } from "./model";
import { Command, Dot, Skeleton } from "../ui/bits";
import type { HealthModel } from "./useHealth";
import { verdict } from "./verdict";
import "./health.css";

export function HealthScreen({ model }: { model: HealthModel }) {
  if (model.load === "unauthorized" || model.load === "down") {
    const down = model.load === "down";
    return (
      <section className="sm-notice" role="alert">
        <Dot severity={down ? "error" : "info"} />
        <div>
          <p className="sm-notice-head">{down ? "Studio's server isn't answering." : "Open Studio from the link it printed."}</p>
          <p className="sm-notice-sub">
            {down
              ? <>It may have stopped. Check the terminal you started it from, or run <code>npx brainforge-studio</code> again in this brain.</>
              : "This page needs the address Studio showed in your terminal when it started. It carries a one-time key, so other sites on this computer cannot read your brain."}
          </p>
          {down && <button className="sm-btn" onClick={model.refresh}>Try again</button>}
        </div>
      </section>
    );
  }
  if (model.load === "loading" || !model.health) return <LoadingSeam />;

  const canon = canonView(model.health);
  const nudge = nudges(model.health);
  const drift = nudge.kind === "ok" ? nudge.items.filter((i) => i.severity === "stale") : [];
  const syncNudges = nudge.kind === "ok" ? nudge.items.filter((i) => i.severity !== "stale") : [];
  const canonIssues = canon.kind === "ok" ? canon.issues : [];
  const all: Issue[] = [...canonIssues, ...drift, ...syncNudges];
  const isNew = canon.kind === "ok" && canon.current === 0 && canonIssues.length === 0 && model.gates.phase === "done" && !model.gates.data.available;
  const v = verdict(all, canon.kind === "ok" ? canon.current : 0, isNew);
  const gates = model.gates.phase === "done" ? sourceRows(model.gates.data) : null;
  const changed = gates?.rows.filter((r) => r.severity === "stale").length ?? 0;

  return (
    <div className={model.load === "refreshing" ? "is-refreshing" : undefined}>
      <div className="sm-verdict" aria-live="polite">
        <h1>{v.head}</h1>
        <p>{v.sub}</p>
        <div className="sm-verdict-meta">
          {model.load === "refreshing" ? "Checking…" : `Checked ${model.checkedAgo}`}
          <button className="sm-link" onClick={model.refresh} disabled={model.load === "refreshing"}>Refresh</button>
        </div>
      </div>

      <div className="sm-strip">
        <Counter side="canon" label="Canon · authored" value={canon.kind === "ok" ? canonIssues.length : "—"} note={canon.kind === "ok" ? `${canon.current} current` : canon.kind === "error" ? "check failed" : "unavailable"} />
        <Counter side="seam" label="The seam" value={nudge.kind === "ok" ? drift.length : "—"} note={nudge.kind === "unavailable" ? "run /upgrade" : drift.length ? "drift to review" : "no drift nudge"} />
        <Counter side="derived" label="Derived · synced" value={gates ? changed : "—"} note={gates ? `of ${gates.rows.length} sources changed` : model.gates.phase === "running" ? "checking…" : "not checked yet"} />
      </div>

      <div className="sm-cols">
        <div className="sm-col sm-col-canon">
          <h2>Canon</h2>
          {canon.kind === "error" && <Broken what="canon-health.sh" detail={canon.detail} />}
          {canon.kind === "unavailable" && <Unavailable what="Canon health" hint={canon.hint} />}
          {canon.kind === "raw" && <pre className="sm-raw">{canon.text}</pre>}
          {canon.kind === "ok" && canonIssues.length === 0 && <p className="sm-empty">Every approved doc is within its review date.</p>}
          {canonIssues.map((i) => <Card key={i.key} issue={i} />)}
          {canon.kind === "ok" && canon.stalled.map((d) => (
            <Card key={d.path} issue={{ key: d.path, severity: "warning", title: "Stalled draft", path: d.path, meta: [d.detail.replace(/ · stalled$/, "")], command: `/approve-canon ${d.path.replace(/^context\/canon\/|\.md$/g, "")}` }} />
          ))}
          {canon.kind === "ok" && canon.open.length > 0 && (
            <details className="sm-open">
              <summary>{canon.open.length} open {canon.open.length === 1 ? "draft" : "drafts"}</summary>
              {canon.open.map((d) => <div key={d.path} className="sm-path">{d.path}</div>)}
            </details>
          )}
        </div>

        <div className="sm-seam" aria-hidden="true" />
        {drift.length > 0 && (
          <div className="sm-bridge" role="note">
            <Dot severity="stale" />
            <div>
              <div className="sm-card-title">{drift[0].title}</div>
              <div className="sm-card-meta">{drift[0].meta[0]}</div>
            </div>
            {drift[0].command && <Command text={drift[0].command} />}
          </div>
        )}
        {nudge.kind === "unavailable" && <div className="sm-bridge sm-bridge-quiet"><Unavailable what="Drift and sync nudges" hint={nudge.hint} /></div>}
        {nudge.kind === "error" && <div className="sm-bridge sm-bridge-quiet"><Broken what="tripwires.sh" detail={nudge.detail} /></div>}

        <div className="sm-col sm-col-derived">
          <div className="sm-col-head">
            <h2>Derived</h2>
            {!(model.gates.phase === "done" && !model.gates.data.available) && (
              <button className="sm-btn sm-btn-primary" onClick={model.runGates} disabled={model.gates.phase === "running"} aria-busy={model.gates.phase === "running"}>
                {model.gates.phase === "running" ? "Checking sources…" : model.gates.phase === "done" ? "Check again" : "Check sources now"}
              </button>
            )}
          </div>
          {syncNudges.map((i) => <Card key={i.key} issue={i} />)}
          <Sources model={model} rows={gates} />
        </div>
      </div>
    </div>
  );
}

function Sources({ model, rows }: { model: HealthModel; rows: ReturnType<typeof sourceRows> | null }) {
  const g = model.gates;
  if (g.phase === "done" && !g.data.available) {
    return <p className="sm-empty">No sources yet. Connect one with <Command text="/add-source" /></p>;
  }
  if (g.phase === "failed") return <Broken what="The source checks" detail="Studio's server didn't answer while checking. Try again." />;
  if (g.phase === "idle") return <p className="sm-empty">Not checked this session. Checking asks each source whether it changed since the last sync. It reads, never writes.</p>;
  if (g.phase === "running") {
    return (
      <div className="sm-scan is-running">
        {["figma", "github", "website", "monday", "ga"].map((t) => (
          <div className="sm-src sm-src-pending" key={t}><span className="sm-pulse" aria-hidden="true" /><span>Checking {t}</span><Skeleton w={120} h={10} /></div>
        ))}
      </div>
    );
  }
  const groupOf = (r: SourceRow) => (r.severity === "stale" ? 0 : r.severity === "ok" ? 2 : 1);
  return (
    <div className="sm-scan is-done">
      <span className="sm-scanline" aria-hidden="true" />
      {rows!.broken.map((b) => <Broken key={b.script} what={b.script} detail={b.detail} />)}
      {rows!.rows.map((r) => (
        <div className="sm-src" key={r.key} style={{ ["--g" as string]: groupOf(r) }}>
          <Dot severity={r.severity} />
          <div className="sm-src-main">
            <div className="sm-src-id"><span className="sm-type">{r.type}</span> {r.id}</div>
            <div className="sm-card-meta" title={r.reason}>{r.status} · {r.reason}</div>
          </div>
          {r.command && <Command text={r.command} />}
        </div>
      ))}
    </div>
  );
}

function Counter({ side, label, value, note }: { side: "canon" | "seam" | "derived"; label: string; value: number | string; note: string }) {
  return (
    <div className={`sm-counter sm-counter-${side}`}>
      <div className="sm-counter-label">{label}</div>
      <div className="sm-counter-value">{value}</div>
      <div className="sm-counter-note">{note}</div>
    </div>
  );
}

function Card({ issue }: { issue: Issue }) {
  return (
    <div className="sm-card">
      <Dot severity={issue.severity} />
      <div className="sm-card-main">
        <div className="sm-card-title">{issue.title}</div>
        {issue.path && <div className="sm-path">{issue.path}</div>}
        {issue.meta.length > 0 && <div className="sm-card-meta">{issue.meta.join(" · ")}</div>}
      </div>
      {issue.command && <Command text={issue.command} />}
    </div>
  );
}

function Broken({ what, detail }: { what: string; detail: string }) {
  return (
    <div className="sm-card sm-broken" role="alert">
      <Dot severity="error" />
      <div className="sm-card-main">
        <div className="sm-card-title">{what} didn't finish</div>
        <div className="sm-path">{detail}</div>
        <div className="sm-card-meta">This is the check failing, not the brain. Run it in a terminal to see why.</div>
      </div>
    </div>
  );
}

function Unavailable({ what, hint }: { what: string; hint: string }) {
  return (
    <div className="sm-card">
      <Dot severity="info" />
      <div className="sm-card-main"><div className="sm-card-title">{what} aren't available here</div><div className="sm-card-meta">{hint}</div></div>
      <Command text="/upgrade" />
    </div>
  );
}

function LoadingSeam() {
  return (
    <div role="status" aria-busy="true" aria-label="Loading health">
      <div className="sm-verdict"><Skeleton w={260} h={24} /><div style={{ height: 8 }} /><Skeleton w={460} h={12} /></div>
      <div className="sm-strip">{[0, 1, 2].map((i) => <div className="sm-counter" key={i}><Skeleton w={90} h={10} /><div style={{ height: 8 }} /><Skeleton w={40} h={24} /></div>)}</div>
      <div className="sm-cols">
        {[0, 1].map((c) => (
          <div className={`sm-col ${c ? "sm-col-derived" : "sm-col-canon"}`} key={c}>
            <Skeleton w={70} h={12} />
            {[0, 1, 2].map((r) => <div className="sm-card" key={r}><Skeleton w={8} h={8} /><div className="sm-card-main"><Skeleton w={160} h={12} /><div style={{ height: 6 }} /><Skeleton w={240} h={10} /></div></div>)}
          </div>
        ))}
        <div className="sm-seam" aria-hidden="true" />
      </div>
    </div>
  );
}
