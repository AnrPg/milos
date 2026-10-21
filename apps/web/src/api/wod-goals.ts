import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * WOD goals (ADR-163): the coach's goals on a workout (muscles with roles,
 * fitness qualities, stimulus) with the live suggestion from its exercises,
 * the member's read of visible goals, and «Τι ένιωσες;» feedback on an
 * execution or a training-log entry.
 */
export type GoalMuscle = components["schemas"]["GoalMuscle"];
export type GoalRole = GoalMuscle["role"];
export type AnatomyTaxonomy = components["schemas"]["AnatomyTaxonomy"];
export type StaffWorkoutGoalsResponse = components["schemas"]["StaffWorkoutGoalsResponse"];
export type StaffWorkoutGoals = StaffWorkoutGoalsResponse["goals"];
export type WorkoutGoalSuggestion = StaffWorkoutGoalsResponse["suggestion"];
export type SaveWorkoutGoalsRequest = components["schemas"]["SaveWorkoutGoalsRequest"];
export type MemberWorkoutGoalsResponse = components["schemas"]["MemberWorkoutGoalsResponse"];
export type MemberWorkoutGoals = NonNullable<MemberWorkoutGoalsResponse["goals"]>;
export type GoalFeedbackResponse = components["schemas"]["GoalFeedbackResponse"];
export type GoalFeedback = NonNullable<GoalFeedbackResponse["feedback"]>;
export type GoalFeedbackEntryKind = GoalFeedbackResponse["entry_kind"];
export type SaveGoalFeedbackRequest = components["schemas"]["SaveGoalFeedbackRequest"];

export const GOAL_ROLES: readonly GoalRole[] = ["primary", "secondary", "stabilizer"];

export const ANATOMY_TAXONOMY_KEY = ["anatomy", "taxonomy"] as const;
export const adminWorkoutGoalsKey = (workoutId: string) => ["admin", "workouts", workoutId, "goals"] as const;
export const workoutGoalsKey = (workoutId: string) => ["workouts", workoutId, "goals"] as const;
export const goalFeedbackKey = (kind: GoalFeedbackEntryKind, entryId: string) => ["my", "goal-feedback", kind, entryId] as const;

const id = (value: string) => encodeURIComponent(value);

export function fetchAnatomyTaxonomy(token: string) {
  return apiRequest<AnatomyTaxonomy>("/anatomy/taxonomy", { token });
}

export function fetchAdminWorkoutGoals(token: string, workoutId: string) {
  return apiRequest<StaffWorkoutGoalsResponse>(`/admin/workouts/${id(workoutId)}/goals`, { token });
}

export function saveAdminWorkoutGoals(token: string, workoutId: string, body: SaveWorkoutGoalsRequest) {
  return apiRequest<StaffWorkoutGoalsResponse>(`/admin/workouts/${id(workoutId)}/goals`, { method: "PUT", token, body });
}

export function fetchWorkoutGoals(token: string, workoutId: string) {
  return apiRequest<MemberWorkoutGoalsResponse>(`/workouts/${id(workoutId)}/goals`, { token });
}

export function fetchGoalFeedback(token: string, kind: GoalFeedbackEntryKind, entryId: string) {
  return apiRequest<GoalFeedbackResponse>(`/me/goal-feedback/${kind}/${id(entryId)}`, { token });
}

export function saveGoalFeedback(token: string, kind: GoalFeedbackEntryKind, entryId: string, body: SaveGoalFeedbackRequest) {
  return apiRequest<GoalFeedbackResponse>(`/me/goal-feedback/${kind}/${id(entryId)}`, { method: "PUT", token, body });
}
