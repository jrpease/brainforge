import { useEffect, useState } from "react";
import { ApiError, getJson } from "../api";
import { Command, Dot, Skeleton } from "../ui/bits";

type Entry = { key: string; type: string; entry: Record<string, unknown>; slot: Record<string, unknown> | null };
type SourcesResponse = { available: true; lastFullSync: string | null; entries: Entry[] } | { available: false; hint: string };

// The sources as sources.json and .sync-state.json record them, shown as-is. Whether a source is
// fresh is /sync-health's call, not this screen's.
export function SourcesScreen() {
  const [data, setData] = useState<SourcesResponse>();
  const [err, setErr] = useState<string>();
  useEffect(() => {
    getJson<SourcesResponse>("/api/sources").then(setData).catch((e) => setErr(e instanceof ApiError && e.kind === "unauthorized" ? "unauthorized" : "down"));
  }, []);

  if (err) return <ErrorNotice kind={err} />;
  if (!data) return <div role="status" aria-busy="true" aria-label="Loading"><div className="screen-head"><h1>Sources</h1></div>{[0, 1, 2].map((i) => <div className="row" key={i}><Skeleton w={240} h={12} /></div>)}</div>;
  if (!data.available) {
    return (
      <section aria-label="Sources">
        <div className="screen-head"><h1>Sources</h1><p>No sources are connected to this brain yet.</p></div>
        <div className="row"><div className="row-main">Connect one in Claude Code with</div><Command text="/add-source" /></div>
      </section>
    );
  }
  return (
    <section aria-label="Sources">
      <div className="screen-head">
        <h1>Sources</h1>
        <p>
          {data.entries.length} {data.entries.length === 1 ? "source" : "sources"} in <span className="mono">sources.json</span>. Last full sync:{" "}
          <span className="mono">{data.lastFullSync ?? "never"}</span>. To see whether they changed upstream, use Check sources now on Health.
        </p>
      </div>
      <div className="rows">
        {data.entries.map((e) => {
          const id = String(e.entry.id ?? "?");
          const synced = e.slot?.synced;
          const enabled = e.entry.enabled !== false;
          return (
            <div className="row" key={`${e.key}:${id}`}>
              <Dot severity={synced === false ? "warning" : enabled ? "info" : "info"} />
              <div className="row-main">
                <div className="mono"><span className="muted">{e.type}</span> {id}</div>
                <div className="row-meta">{String(e.entry.label ?? e.entry.remote ?? e.entry.url ?? "")}</div>
              </div>
              <div className="row-meta mono">{String(e.entry.into ?? "")}</div>
              <div className="row-meta">
                {[enabled ? String(e.entry.cadence ?? "") : "disabled", synced === false ? "never synced" : synced === true ? "synced" : "no sync record"].filter(Boolean).join(" · ")}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

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
