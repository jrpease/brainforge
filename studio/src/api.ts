// Every call to Studio's own server. The launch link's token arrives as an httpOnly cookie, so a
// 401 means this tab was opened some other way.
export class ApiError extends Error {
  constructor(public kind: "unauthorized" | "down" | "http", public status?: number) {
    super(kind);
  }
}

async function call(path: string, init?: RequestInit) {
  let r: Response;
  try {
    r = await fetch(path, { credentials: "same-origin", ...init });
  } catch {
    throw new ApiError("down");
  }
  if (r.status === 401) throw new ApiError("unauthorized", 401);
  if (!r.ok) throw new ApiError("http", r.status);
  return r;
}

export const getJson = async <T,>(path: string, init?: RequestInit): Promise<T> => (await call(path, init)).json();
export const getText = async (path: string): Promise<string> => (await call(path)).text();
