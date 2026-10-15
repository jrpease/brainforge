// The API's shapes, as the server returns them (server/app.ts, server/scripts.ts).
export type Unavailable = { available: false; hint: string };

export type ScriptRun = {
  available: true;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
  error: boolean;
};

export type CanonRun = ScriptRun & { finding: boolean };
export type TripwiresRun = ScriptRun & { lines: string[] };

export type HealthResponse = { canon: CanonRun | Unavailable; tripwires: TripwiresRun | Unavailable };

export type GateLine = {
  type?: string;
  id?: string;
  status?: "unchanged" | "changed" | "never" | "not-checked" | "blocked" | "unparsed" | string;
  reason?: string;
  delta?: unknown[];
  [k: string]: unknown;
};

export type GateRun = ScriptRun & { script: string; lines: GateLine[] };
export type GatesResponse = { available: true; results: GateRun[] } | Unavailable;

export type BrainInfo = { path: string; name: string };
