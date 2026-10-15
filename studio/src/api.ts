// Every call to Studio's own server, each carrying the launch token as a header. A 401 means this
// tab was opened some other way than the printed link.
export class ApiError extends Error {
  constructor(public kind: "unauthorized" | "down" | "http", public status?: number) {
    super(kind);
  }
}

// The launch link carries ?t=<token>. Keep it for this tab only and take it out of the address bar.
const KEY = "brainforge-studio-token";
function token(): string {
  const fromUrl = new URLSearchParams(location.search).get("t");
  if (fromUrl) {
    try {
      sessionStorage.setItem(KEY, fromUrl);
    } catch {
      // storage blocked: the token lives in memory for this page load
    }
    memory = fromUrl;
    const url = new URL(location.href);
    url.searchParams.delete("t");
    history.replaceState(null, "", url.pathname + url.search + url.hash);
  }
  if (memory) return memory;
  try {
    memory = sessionStorage.getItem(KEY) ?? "";
  } catch {
    memory = "";
  }
  return memory;
}
let memory = "";
token();

async function call(path: string, init?: RequestInit) {
  let r: Response;
  try {
    r = await fetch(path, { ...init, headers: { ...(init?.headers ?? {}), "x-studio-token": token() } });
  } catch {
    throw new ApiError("down");
  }
  if (r.status === 401) throw new ApiError("unauthorized", 401);
  if (!r.ok) throw new ApiError("http", r.status);
  return r;
}

export const getJson = async <T,>(path: string, init?: RequestInit): Promise<T> => (await call(path, init)).json();
export const getText = async (path: string): Promise<string> => (await call(path)).text();
