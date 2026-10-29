/**
 * ADR-270: a plan run survives a reload. Like the free-text runner's own
 * clock (`lib/free-text-timer`), progress lives in this device's
 * localStorage, keyed by execution id, and is cleared once the execution is
 * completed. Storage can be missing or full: every access is guarded.
 */
import type { PlanSetActual, SectionScore } from "@/api/executions";

import type { PlanRunSnapshot } from "./PlanExecution";

export type PlanProgress = {
  /** The section being run. */
  index: number;
  scores: SectionScore[];
  elapsed: Record<string, number>;
  actuals: Record<string, PlanSetActual[]>;
  /** The running section's own state. */
  current: PlanRunSnapshot | null;
  /** Every section is done and the finish wizard is open. */
  finishing: boolean;
};

const key = (executionId: string) => `palee:plan-run:${executionId}`;

export function readPlanProgress(executionId: string): PlanProgress | null {
  try {
    const raw = window.localStorage.getItem(key(executionId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PlanProgress>;
    if (typeof parsed.index !== "number") return null;
    return {
      index: parsed.index,
      scores: parsed.scores ?? [],
      elapsed: parsed.elapsed ?? {},
      actuals: parsed.actuals ?? {},
      current: parsed.current ?? null,
      finishing: Boolean(parsed.finishing),
    };
  } catch {
    return null;
  }
}

export function storePlanProgress(executionId: string, progress: PlanProgress | null): void {
  try {
    if (progress) window.localStorage.setItem(key(executionId), JSON.stringify(progress));
    else window.localStorage.removeItem(key(executionId));
  } catch {
    // Progress is a convenience: without storage the run still works, it just starts over after a reload.
  }
}
