// The comps' data layer: the same states the real app will see, served from fixtures.
import { useCallback, useEffect, useState } from "react";
import type { GatesResponse, HealthResponse } from "../../src/lib/types";
import { GATES, GATES_SHOWN, HEALTH, type StateName } from "./fixtures";

export type Load = "loading" | "ready" | "refreshing" | "down" | "unauthorized";
export type GatesState = { phase: "idle" } | { phase: "running" } | { phase: "done"; data: GatesResponse };

export type HealthModel = {
  load: Load;
  health?: HealthResponse;
  gates: GatesState;
  checkedAgo: string;
  refresh: () => void;
  runGates: () => void;
};

export function useHealth(state: StateName, animate: boolean): HealthModel {
  const frozen = (s: StateName): Load =>
    s === "initial-load" ? "loading" : s === "server-down" ? "down" : s === "unauthorized" ? "unauthorized" : s === "refresh" ? "refreshing" : "ready";
  const [load, setLoad] = useState<Load>(frozen(state));
  const [gates, setGates] = useState<GatesState>(
    state === "gates-running" ? { phase: "running" } : GATES_SHOWN[state] && GATES[state] ? { phase: "done", data: GATES[state]! } : { phase: "idle" },
  );
  useEffect(() => {
    setLoad(frozen(state));
    setGates(state === "gates-running" ? { phase: "running" } : GATES_SHOWN[state] && GATES[state] ? { phase: "done", data: GATES[state]! } : { phase: "idle" });
  }, [state]);

  const refresh = useCallback(() => {
    setLoad("refreshing");
    setTimeout(() => setLoad("ready"), 900);
  }, []);
  const runGates = useCallback(() => {
    setGates({ phase: "running" });
    if (!animate) return;
    setTimeout(() => setGates({ phase: "done", data: GATES[state] ?? GATES["gates-mixed"]! }), 1600);
  }, [animate, state]);

  return { load, health: HEALTH[state], gates, checkedAgo: "just now", refresh, runGates };
}
