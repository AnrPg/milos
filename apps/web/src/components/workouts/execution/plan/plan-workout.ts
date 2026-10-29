/**
 * ADR-270: which workouts run in the plan runner, and their runnable
 * sections. A workout written in the structured editor has authoring mode
 * `structured_plan` and one `plan` (a `PlanSection`) per section.
 */
import { PLAN_VERSION, type PlanSection } from "@/lib/structured-plan/types";

export const STRUCTURED_PLAN_MODE = "structured_plan";

type WorkoutLike = {
  authoring_mode?: string | null;
  sections?: ReadonlyArray<{ id?: string | null; name?: string | null; order?: number | null; plan?: unknown }> | null;
};

const FLOWS = new Set(["sets", "for_time", "amrap", "emom", "intervals", "rest"]);

/** A stored plan the runner can read (shape only: the API validated its values). */
export function isPlanSection(value: unknown): value is PlanSection {
  if (!value || typeof value !== "object") return false;
  const v = value as Partial<PlanSection>;
  return (
    v.v === PLAN_VERSION &&
    typeof v.flow === "string" &&
    FLOWS.has(v.flow) &&
    typeof v.params === "object" &&
    v.params !== null &&
    Array.isArray(v.blocks) &&
    v.blocks.every((b) => Array.isArray(b))
  );
}

/** The workout runs in the plan runner (written in the structured editor). */
export function usesPlanRunner(workout: { authoring_mode?: string | null } | null | undefined): boolean {
  return workout?.authoring_mode === STRUCTURED_PLAN_MODE;
}

export type RunnablePlanSection = { id: string; name: string; plan: PlanSection };

/** The workout's plan sections, in order. */
export function planSections(workout: WorkoutLike | null | undefined): RunnablePlanSection[] {
  return [...(workout?.sections ?? [])]
    .map((section, index) => ({ section, index }))
    .sort((a, b) => (a.section.order ?? a.index) - (b.section.order ?? b.index))
    .flatMap(({ section, index }) =>
      isPlanSection(section.plan)
        ? [{ id: section.id ?? `section-${index}`, name: section.name ?? "", plan: section.plan }]
        : [],
    );
}
