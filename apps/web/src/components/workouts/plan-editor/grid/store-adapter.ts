/**
 * The grid's only door to the editor store (`@/stores/structured-plan`,
 * agent 3). It reads one section's plan and writes a whole new plan back
 * (built by `mutations.ts`); `typing` lets the store coalesce keystrokes into
 * one undo step.
 *
 * TEMPORARY: until plan/3-shell lands, a minimal local zustand store stands
 * in for the editor store. Only this file changes when it lands.
 */
import { useCallback, useMemo } from "react";
import { create } from "zustand";

import type { PlanSection } from "@/lib/structured-plan/types";

type ShimState = {
  plans: Record<string, PlanSection>;
  setPlan: (sectionId: string, plan: PlanSection) => void;
};

export const usePlanStoreShim = create<ShimState>((set) => ({
  plans: {},
  setPlan: (sectionId, plan) => set((state) => ({ plans: { ...state.plans, [sectionId]: plan } })),
}));

export function usePlanSection(sectionId: string): PlanSection | undefined {
  return usePlanStoreShim((state) => state.plans[sectionId]);
}

export type PlanWriter = (recipe: (plan: PlanSection) => PlanSection, opts?: { typing?: boolean }) => void;

export function usePlanWriter(sectionId: string): PlanWriter {
  return useCallback<PlanWriter>(
    (recipe) => {
      const state = usePlanStoreShim.getState();
      const plan = state.plans[sectionId];
      if (plan) state.setPlan(sectionId, recipe(plan));
    },
    [sectionId],
  );
}

/** Tests and harnesses: put a section into the store. */
export function seedPlan(sectionId: string, plan: PlanSection) {
  usePlanStoreShim.getState().setPlan(sectionId, plan);
}

export function readPlan(sectionId: string): PlanSection | undefined {
  return usePlanStoreShim.getState().plans[sectionId];
}

const NO_NAMES: string[] = [];

/** Exercise names already written anywhere in this WOD (every section), for suggestions. */
export function useWodExerciseNames(): string[] {
  const plans = usePlanStoreShim((state) => state.plans);
  return useMemo(() => {
    const names = new Set<string>();
    for (const plan of Object.values(plans))
      for (const list of [...plan.blocks, plan.interrupt ?? []]) for (const row of list) if (row.kind === "ex" && row.name.trim()) names.add(row.name.trim());
    return names.size ? [...names] : NO_NAMES;
  }, [plans]);
}
