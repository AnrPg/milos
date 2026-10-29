import type { TrainingGoal } from "@/api/gamification";

/** ADR-229: the bounds the API accepts; the API sends them too. */
export const GOAL_MIN = 1;
export const GOAL_MAX = 14;
export const GOAL_DEFAULT = 2;

export function goalBounds(goal?: Pick<TrainingGoal, "min" | "max"> | null) {
  return { min: goal?.min ?? GOAL_MIN, max: goal?.max ?? GOAL_MAX };
}

/** A step of the stepper, kept inside the bounds the API accepts. */
export function stepGoal(current: number, delta: number, bounds = goalBounds()) {
  return Math.min(bounds.max, Math.max(bounds.min, Math.round(current) + delta));
}

/** The target that applies: the goal's, else the platform default. */
export function weeklyTarget(goal?: Pick<TrainingGoal, "weekly_workout_target"> | null) {
  return goal?.weekly_workout_target ?? GOAL_DEFAULT;
}

export type GoalSetterNote =
  | { kind: "default" }
  | { kind: "self" }
  | { kind: "coach" | "staff"; name: string };

/** What to say about who set the goal (the member keeps the last word). */
export function goalSetterNote(goal?: TrainingGoal | null): GoalSetterNote {
  if (!goal || goal.is_default || !goal.set_by_role) return { kind: "default" };
  if (goal.set_by_role === "self") return { kind: "self" };
  return { kind: goal.set_by_role, name: goal.set_by_nickname ?? "" };
}
