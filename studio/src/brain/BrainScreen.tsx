import { useEffect, useState } from "react";
import { ApiError, getJson, getText } from "../api";
import { Command, Skeleton } from "../ui/bits";
import { ErrorNotice } from "../sources/SourcesScreen";
import "./brain.css";
import { Markdown } from "./markdown";

type File = { path: string; title?: string; tokens?: number };
type Domain = { path: string; title?: string; tokens?: number; band?: string; files?: File[] };
type ManifestResponse = { available: true; manifest: { domains?: Domain[]; generatedAt?: string } } | { available: false; hint: string };

const splitFrontmatter = (text: string) => {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!m) return { fields: [] as Array<[string, string]>, body: text };
  const fields = m[1].split("\n").map((l) => l.match(/^([\w-]+):\s*(.*)$/)).filter(Boolean).map((x) => [x![1], x![2]] as [string, string]);
  return { fields, body: text.slice(m[0].length) };
};

export function BrainScreen() {
  const [data, setData] = useState<ManifestResponse>();
  const [err, setErr] = useState<string>();
  const [open, setOpen] = useState<string>();
  const [doc, setDoc] = useState<{ path: string; text: string } | { path: string; error: string }>();

  useEffect(() => {
    getJson<ManifestResponse>("/api/manifest").then(setData).catch((e) => setErr(e instanceof ApiError && e.kind === "unauthorized" ? "unauthorized" : "down"));
  }, []);
  useEffect(() => {
    if (!open) return;
    setDoc(undefined);
    getText(`/api/file?path=${encodeURIComponent(open)}`)
      .then((text) => setDoc({ path: open, text }))
      .catch(() => setDoc({ path: open, error: "This file couldn't be read. It may have moved since the manifest was generated." }));
  }, [open]);

  if (err) return <ErrorNotice kind={err} />;
  if (!data) return <div role="status" aria-busy="true" aria-label="Loading"><div className="screen-head"><h1>Brain</h1></div>{[0, 1, 2, 3].map((i) => <div className="row" key={i}><Skeleton w={220} h={12} /></div>)}</div>;
  if (!data.available) {
    return (
      <section aria-label="Brain">
        <div className="screen-head"><h1>Brain</h1><p>This brain has no manifest yet, so there is nothing to browse. Upgrading adds the generator that writes it.</p></div>
        <div className="row"><div className="row-main">In Claude Code, run</div><Command text="/upgrade" /></div>
      </section>
    );
  }
  const domains = data.manifest.domains ?? [];
  const canon = domains.filter((d) => d.path.includes("/canon/"));
  const derived = domains.filter((d) => !d.path.includes("/canon/"));

  return (
    <section aria-label="Brain" className="br">
      <div className="screen-head">
        <h1>Brain</h1>
        <p>{domains.length} domains from <span className="mono">brain-manifest.json</span>{data.manifest.generatedAt ? `, generated ${data.manifest.generatedAt}` : ""}.</p>
      </div>
      <div className="br-split">
        <nav className="br-tree" aria-label="Domains">
          {([["Canon", "canon", canon], ["Derived", "derived", derived]] as const).map(([label, side, list]) => (
            <div key={side} className={`br-side br-side-${side}`}>
              <h2>{label}</h2>
              {list.length === 0 && <p className="muted br-none">None yet.</p>}
              {list.map((d) => (
                <div key={d.path} className="br-domain">
                  <div className="br-domain-head">
                    <span className="br-domain-title">{d.title ?? d.path.split("/").pop()}</span>
                    <span className="muted mono">{d.tokens ?? 0} tok</span>
                  </div>
                  {(d.files ?? []).map((f) => {
                    const full = `${d.path}/${f.path}`;
                    return (
                      <button key={full} type="button" className="br-file" aria-current={open === full ? "true" : undefined} onClick={() => setOpen(full)}>
                        <span className="br-file-title">{f.title ?? f.path}</span>
                        <span className="muted mono">{f.tokens ?? 0}</span>
                      </button>
                    );
                  })}
                </div>
              ))}
            </div>
          ))}
        </nav>
        <article className="br-doc" aria-live="polite">
          {!open && <p className="muted br-pick">Pick a file to read it here. Studio only reads; edits still go through Claude Code and a PR.</p>}
          {open && !doc && <div role="status" aria-busy="true" aria-label="Loading"><Skeleton w={300} h={20} /><div style={{ height: 12 }} /><Skeleton w="90%" h={12} /><div style={{ height: 6 }} /><Skeleton w="80%" h={12} /></div>}
          {doc && "error" in doc && <p className="br-err">{doc.error}</p>}
          {doc && "text" in doc && <Doc path={doc.path} text={doc.text} />}
        </article>
      </div>
    </section>
  );
}

function Doc({ path, text }: { path: string; text: string }) {
  const { fields, body } = splitFrontmatter(text);
  return (
    <>
      <div className="mono muted br-doc-path">{path}</div>
      {fields.length > 0 && (
        <dl className="br-fields">
          {fields.map(([k, v]) => (
            <div key={k}><dt>{k}</dt><dd className={k === "status" && v === "draft" ? "br-draft" : undefined}>{v}</dd></div>
          ))}
        </dl>
      )}
      <div className="br-body"><Markdown text={body} /></div>
    </>
  );
}
