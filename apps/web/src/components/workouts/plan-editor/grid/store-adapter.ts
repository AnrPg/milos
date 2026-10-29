/**
 * The grid's only door to the editor store (`@/stores/structured-plan`). It
 * reads one section's plan and writes a whole new plan back (built by the
 * pure functions of `mutations.ts`) through `updatePlan`, which keeps the
 * undo history; `typing` coalesces keystrokes into one undo step. The store
 * applies a recipe synchronously, so callers may read ids it created.
 */
import { useCallback, useMemo } from "react";

import type { PlanSection } from "@/lib/structured-plan/types";
import { usePlanEditorStore } from "@/stores/structured-plan";

export function usePlanSection(sectionId: string): PlanSection | undefined {
  return usePlanEditorStore((state) => state.sections.find((x) => x.id === sectionId)?.plan);
}

export type PlanWriter = (recipe: (plan: PlanSection) => PlanSection, opts?: { typing?: boolean }) => void;

export function usePlanWriter(sectionId: string): PlanWriter {
  return useCallback<PlanWriter>(
    (recipe, opts) => usePlanEditorStore.getState().updatePlan(sectionId, recipe, { typing: opts?.typing }),
    [sectionId],
  );
}

/** Asks for the caret on a field (`r:<row>:<field>`, `c:<row>:<col>:<key>`); whoever renders it consumes the key. */
export const requestFocus = (key: string) => usePlanEditorStore.getState().setFocus(key);
export const usePendingFocus = () => usePlanEditorStore((state) => state.pendingFocus);
export const consumeFocus = (key: string) => usePlanEditorStore.getState().consumeFocus(key);

const NO_NAMES: string[] = [];

/** Exercise names already written anywhere in this WOD (every section), for suggestions. */
export function useWodExerciseNames(): string[] {
  const sections = usePlanEditorStore((state) => state.sections);
  return useMemo(() => {
    const names = new Set<string>();
    for (const { plan } of sections)
      for (const list of [...plan.blocks, plan.interrupt ?? []]) for (const row of list) if (row.kind === "ex" && row.name.trim()) names.add(row.name.trim());
    return names.size ? [...names] : NO_NAMES;
  }, [sections]);
}

/** Tests and harnesses: a WOD of one section holding `plan`. */
export function seedPlan(sectionId: string, plan: PlanSection) {
  usePlanEditorStore.getState().load({ title: "", note: "", sections: [{ id: sectionId, name: "", plan }] });
}

export function readPlan(sectionId: string): PlanSection | undefined {
  return usePlanEditorStore.getState().sections.find((x) => x.id === sectionId)?.plan;
}
