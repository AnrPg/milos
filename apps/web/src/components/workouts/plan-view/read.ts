import { PLAN_VERSION, type PlanSection } from "@/lib/structured-plan/types";

import type { PlanViewSource } from "./PlanView";

/** ADR-270: how a workout written in the structured plan editor is stored. */
export const STRUCTURED_PLAN_MODE = "structured_plan";

type SectionLike = { id?: string | null; name?: string | null; plan?: unknown };

const FLOWS = new Set(["sets", "for_time", "amrap", "emom", "intervals", "rest"]);

/** Whether a stored value reads as a plan section (version and shape); anything else is ignored. */
export function isPlanSection(value: unknown): value is PlanSection {
  if (!value || typeof value !== "object") return false;
  const plan = value as Partial<PlanSection>;
  return (
    plan.v === PLAN_VERSION &&
    typeof plan.flow === "string" &&
    FLOWS.has(plan.flow) &&
    Boolean(plan.params) &&
    typeof plan.params === "object" &&
    Array.isArray(plan.blocks) &&
    plan.blocks.every((block) => Array.isArray(block))
  );
}

/** The plan sections of a workout, in order; [] when it was not written as a plan. */
export function readPlanSections(workout: { authoring_mode?: string | null; sections?: SectionLike[] | null } | null | undefined): PlanViewSource[] {
  if (!workout || workout.authoring_mode !== STRUCTURED_PLAN_MODE) return [];
  return (workout.sections ?? []).flatMap((section) =>
    isPlanSection(section.plan) ? [{ id: section.id ?? null, name: section.name ?? "", plan: section.plan }] : [],
  );
}

export type PlanSummaryEntry = { name: string; flow: PlanSection["flow"]; exerciseCount: number };

/** Exercise rows with a name, in every block and the interruption. */
export function planExerciseCount(plan: PlanSection): number {
  return [...plan.blocks.flat(), ...(plan.interrupt ?? [])].filter((row) => row.kind === "ex" && row.name.trim()).length;
}

type BodyLike = { kind?: unknown; sections?: unknown };
type SummarySection = { name?: unknown; flow?: unknown; exercise_count?: unknown; plan?: unknown };

/**
 * ADR-224 / ADR-270: one line per section of a plan workout for lists (name,
 * flow, exercise count), from the list's `body` summary (kind `plan`), a full
 * `plan` body, or the sections' own plans. [] for any other workout.
 */
export function readPlanSummary(workout: { authoring_mode?: string | null; body?: unknown; sections?: SectionLike[] | null }): PlanSummaryEntry[] {
  const body = workout.body as BodyLike | null | undefined;
  if (body?.kind === "plan" && Array.isArray(body.sections)) {
    return (body.sections as SummarySection[]).flatMap((section) => {
      const name = typeof section.name === "string" ? section.name : "";
      if (isPlanSection(section.plan)) return [{ name, flow: section.plan.flow, exerciseCount: planExerciseCount(section.plan) }];
      if (typeof section.flow === "string" && FLOWS.has(section.flow)) {
        const count = typeof section.exercise_count === "number" ? section.exercise_count : 0;
        return [{ name, flow: section.flow as PlanSection["flow"], exerciseCount: count }];
      }
      return [];
    });
  }
  return readPlanSections(workout).map((section) => ({
    name: section.name ?? "",
    flow: section.plan.flow,
    exerciseCount: planExerciseCount(section.plan),
  }));
}
