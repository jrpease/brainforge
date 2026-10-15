import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, getJson } from "../api";
import type { GatesResponse, HealthResponse } from "../lib/types";

export type Load = "loading" | "ready" | "refreshing" | "down" | "unauthorized";
export type GatesState = { phase: "idle" } | { phase: "running" } | { phase: "done"; data: GatesResponse } | { phase: "failed" };

export type HealthModel = {
  load: Load;
  health?: HealthResponse;
  gates: GatesState;
  checkedAgo: string;
  refresh: () => void;
  runGates: () => void;
};

const ago = (t: number | null) => {
  if (!t) return "";
  const s = Math.round((Date.now() - t) / 1000);
  if (s < 10) return "just now";
  if (s < 60) return `${s} seconds ago`;
  const m = Math.round(s / 60);
  return m === 1 ? "a minute ago" : `${m} minutes ago`;
};

const failure = (e: unknown): Load => (e instanceof ApiError && e.kind === "unauthorized" ? "unauthorized" : "down");

export function useHealth(): HealthModel {
  const [load, setLoad] = useState<Load>("loading");
  const [health, setHealth] = useState<HealthResponse>();
  const [gates, setGates] = useState<GatesState>({ phase: "idle" });
  const [checkedAt, setCheckedAt] = useState<number | null>(null);
  const [, tick] = useState(0);
  const had = useRef(false);

  const fetchHealth = useCallback(async () => {
    setLoad(had.current ? "refreshing" : "loading");
    try {
      setHealth(await getJson<HealthResponse>("/api/health"));
      had.current = true;
      setCheckedAt(Date.now());
      setLoad("ready");
    } catch (e) {
      setLoad(failure(e));
    }
  }, []);

  const runGates = useCallback(async () => {
    setGates({ phase: "running" });
    try {
      setGates({ phase: "done", data: await getJson<GatesResponse>("/api/gates/run", { method: "POST" }) });
    } catch (e) {
      if (e instanceof ApiError && e.kind === "unauthorized") setLoad("unauthorized");
      setGates({ phase: "failed" });
    }
  }, []);

  useEffect(() => {
    fetchHealth();
    const t = setInterval(() => tick((n) => n + 1), 15_000);
    return () => clearInterval(t);
  }, [fetchHealth]);

  return { load, health, gates, checkedAgo: ago(checkedAt), refresh: fetchHealth, runGates };
}
