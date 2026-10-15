import type { BrainInfo } from "../../../src/lib/types";
import { canonView, nudges, sourceRows, type Issue } from "../model";
import { Command, Dot, Skeleton, ThemeToggle } from "../shared/bits";
import type { HealthModel } from "../useHealth";
import { verdict } from "../verdict";
import "./ledger.css";

type Props = { brain: BrainInfo; model: HealthModel; theme: "dark" | "light"; onTheme: () => void };

export function HealthLedger({ brain, model, theme, onTheme }: Props) {
  return (
    <div className="lg">
      <aside className="lg-side">
        <div className="lg-mark">Brainforge <em>Studio</em></div>
        <div className="lg-brain">
          <div className="lg-brain-name">{brain.name}</div>
          <div className="lg-brain-path" title={brain.path}>{brain.path}</div>
        </div>
        <nav className="lg-nav" aria-label="Screens">
          <a aria-current="page" href="#health">Health</a>
          <a href="#brain">Brain</a>
          <a href="#sources">Sources</a>
        </nav>
        <div className="lg-side-foot"><ThemeToggle theme={theme} onTheme={onTheme} /></div>
      </aside>
      <main className="lg-main">
        <Body model={model} />
      </main>
    </div>
  );
}

function Body({ model }: { model: HealthModel }) {
  if (model.load === "unauthorized") {
    return (
      <Notice title="Open Studio from the link it printed." severity="info">
        This page needs the address Studio showed in your terminal when it started. It carries a one-time key, so other
        sites on this computer cannot read your brain. Copy that link into this tab.
      </Notice>
    );
  }
  if (model.load === "down") {
    return (
      <Notice title="Studio's server isn't answering." severity="error" action={<button className="lg-btn" onClick={model.refresh}>Try again</button>}>
        It may have stopped. Check the terminal you started it from, or run <code>npx brainforge-studio</code> again in this brain.
      </Notice>
    );
  }
  if (model.load === "loading" || !model.health) return <LoadingLedger />;

  const canon = canonView(model.health);
  const nudge = nudges(model.health);
  const needs: Issue[] = [...(canon.kind === "ok" ? canon.issues : []), ...(nudge.kind === "ok" ? nudge.items : [])];
  const isNew = canon.kind === "ok" && canon.current === 0 && canon.issues.length === 0 && model.gates.phase === "done" && !model.gates.data.available;
  const v = verdict(needs, canon.kind === "ok" ? canon.current : 0, isNew);

  return (
    <>
      <header className="lg-head">
        <h1>Health</h1>
        <div className="lg-head-meta">
          <span>{model.load === "refreshing" ? "Checking…" : `Checked ${model.checkedAgo}`}</span>
          <button className="lg-btn" onClick={model.refresh} disabled={model.load === "refreshing"}>Refresh</button>
        </div>
      </header>

      <section className={`lg-verdict${model.load === "refreshing" ? " is-refreshing" : ""}`} aria-live="polite">
        <Dot severity={needs.length ? (needs.some((i) => i.severity === "stale") ? "stale" : "warning") : "ok"} />
        <div>
          <p className="lg-verdict-head">{v.head}</p>
          <p className="lg-verdict-sub">{v.sub}</p>
        </div>
      </section>

      <Section title="Needs you" count={needs.length} empty={needs.length === 0 ? "Nothing here. Canon is current and no nudges are firing." : undefined}>
        {canon.kind === "error" && <Broken what="canon-health.sh" detail={canon.detail} />}
        {canon.kind === "raw" && <pre className="lg-raw">{canon.text}</pre>}
        {needs.map((i) => <IssueRow key={i.key} issue={i} />)}
        {nudge.kind === "unavailable" && <Unavailable what="Drift and sync nudges" hint={nudge.hint} />}
        {nudge.kind === "error" && <Broken what="tripwires.sh" detail={nudge.detail} />}
      </Section>

      <SourcesSection model={model} />

      {canon.kind === "ok" && (canon.stalled.length > 0 || canon.open.length > 0) && (
        <Section title="Drafts" count={canon.stalled.length + canon.open.length}>
          {canon.stalled.map((d) => (
            <div className="lg-row" key={d.path}>
              <Dot severity="warning" />
              <div className="lg-row-main"><div className="lg-row-title">Stalled draft</div><div className="lg-path">{d.path}</div></div>
              <div className="lg-row-meta">{d.detail.replace(/ · stalled$/, "")}</div>
              <div className="lg-row-act"><Command text={`/approve-canon ${d.path.replace(/^context\/canon\/|\.md$/g, "")}`} /></div>
            </div>
          ))}
          {canon.open.length > 0 && (
            <details className="lg-open">
              <summary>{canon.open.length} open {canon.open.length === 1 ? "draft" : "drafts"}, touched in the last 30 days</summary>
              {canon.open.map((d) => <div className="lg-path lg-open-row" key={d.path}>{d.path}</div>)}
            </details>
          )}
        </Section>
      )}
    </>
  );
}

function SourcesSection({ model }: { model: HealthModel }) {
  const g = model.gates;
  const running = g.phase === "running";
  const action = (
    <button className="lg-btn lg-btn-primary" onClick={model.runGates} disabled={running} aria-busy={running}>
      {running ? "Checking sources…" : g.phase === "done" ? "Check again" : "Check sources now"}
    </button>
  );
  if (g.phase === "done" && !g.data.available) {
    return (
      <Section title="Sources" action={null}>
        <div className="lg-empty">No sources yet. Connect one with <Command text="/add-source" /> and its checks show up here.</div>
      </Section>
    );
  }
  if (g.phase === "idle") {
    return (
      <Section title="Sources" action={action}>
        <div className="lg-empty">Not checked this session. Checking asks each source whether it changed since the last sync. It reads, never writes.</div>
      </Section>
    );
  }
  if (running) {
    return (
      <Section title="Sources" action={action}>
        {["figma", "github", "website", "monday", "ga"].map((t, i) => (
          <div className="lg-row lg-row-pending" key={t} style={{ ["--i" as string]: i }}>
            <span className="lg-spin" aria-hidden="true" />
            <div className="lg-row-main"><div className="lg-row-title">Checking {t}</div></div>
            <Skeleton w={160} h={10} />
          </div>
        ))}
      </Section>
    );
  }
  const { rows, broken } = sourceRows(g.data);
  const groupOf = (s: string) => (s === "stale" ? 0 : s === "ok" ? 2 : 1);
  return (
    <Section title="Sources" count={rows.length} action={action}>
      {broken.map((b) => <Broken key={b.script} what={b.script} detail={b.detail} />)}
      <div className="lg-reveal">
        {rows.map((r) => (
          <div className="lg-row" key={r.key} style={{ ["--g" as string]: groupOf(r.severity) }}>
            <Dot severity={r.severity} />
            <div className="lg-row-main">
              <div className="lg-row-title">{r.status}</div>
              <div className="lg-path"><span className="lg-type">{r.type}</span> {r.id}</div>
            </div>
            <div className="lg-row-meta" title={r.reason}>{r.reason}</div>
            <div className="lg-row-act">{r.command && <Command text={r.command} />}</div>
          </div>
        ))}
      </div>
    </Section>
  );
}

function IssueRow({ issue }: { issue: Issue }) {
  return (
    <div className="lg-row">
      <Dot severity={issue.severity} />
      <div className="lg-row-main">
        <div className="lg-row-title">{issue.title}</div>
        {issue.path && <div className="lg-path">{issue.path}</div>}
      </div>
      <div className="lg-row-meta">{issue.meta.join(" · ")}</div>
      <div className="lg-row-act">{issue.command && <Command text={issue.command} />}</div>
    </div>
  );
}

function Section({ title, count, action, empty, children }: { title: string; count?: number; action?: React.ReactNode; empty?: string; children?: React.ReactNode }) {
  return (
    <section className="lg-sec" aria-label={title}>
      <div className="lg-sec-head">
        <h2>{title}{count !== undefined && count > 0 && <span className="lg-count">{count}</span>}</h2>
        {action}
      </div>
      <div className="lg-sec-body">
        {children}
        {empty && <div className="lg-empty">{empty}</div>}
      </div>
    </section>
  );
}

function Broken({ what, detail }: { what: string; detail: string }) {
  return (
    <div className="lg-row lg-broken" role="alert">
      <Dot severity="error" />
      <div className="lg-row-main">
        <div className="lg-row-title">{what} didn't finish</div>
        <div className="lg-path">{detail}</div>
      </div>
      <div className="lg-row-meta">This is the check failing, not the brain. Run it in a terminal to see why.</div>
    </div>
  );
}

function Unavailable({ what, hint }: { what: string; hint: string }) {
  return (
    <div className="lg-row lg-unavail">
      <Dot severity="info" />
      <div className="lg-row-main"><div className="lg-row-title">{what} aren't available here</div><div className="lg-path">{hint}</div></div>
      <div className="lg-row-act"><Command text="/upgrade" /></div>
    </div>
  );
}

function Notice({ title, severity, action, children }: { title: string; severity: "info" | "error"; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <>
      <header className="lg-head"><h1>Health</h1></header>
      <section className="lg-verdict" role="alert">
        <Dot severity={severity} />
        <div>
          <p className="lg-verdict-head">{title}</p>
          <p className="lg-verdict-sub">{children}</p>
          {action && <div className="lg-notice-act">{action}</div>}
        </div>
      </section>
    </>
  );
}

function LoadingLedger() {
  return (
    <div aria-busy="true" aria-label="Loading health">
      <header className="lg-head"><h1>Health</h1></header>
      <section className="lg-verdict"><Skeleton w={8} h={8} /><div style={{ flex: 1 }}><Skeleton w={220} h={18} /><div style={{ height: 8 }} /><Skeleton w={420} h={12} /></div></section>
      {[0, 1].map((s) => (
        <section className="lg-sec" key={s}>
          <div className="lg-sec-head"><Skeleton w={90} h={12} /></div>
          <div className="lg-sec-body">
            {[0, 1, 2].map((r) => (
              <div className="lg-row" key={r}><Skeleton w={8} h={8} /><div className="lg-row-main"><Skeleton w={180} h={12} /><div style={{ height: 6 }} /><Skeleton w={260} h={10} /></div><Skeleton w={200} h={10} /></div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
