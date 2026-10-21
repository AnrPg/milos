import { apiRequest } from "@/api/client";
import type { components, operations } from "@/api/generated/schema";

// ADR-174: AI scaling suggestions. Coaches review them under /staff; the
// member reads only a coach-approved adaptation; owners and admins manage the
// gym's AI settings (own key, write-only) under /admin.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;

type QueueResponse = Json<operations["PaleeWeb.StaffScalingController.index"]["responses"][200]>;
type SuggestionResponse = Json<operations["PaleeWeb.StaffScalingController.approve"]["responses"][200]>;
type MemberResponse = Json<operations["PaleeWeb.MyScalingController.show"]["responses"][200]>;
type SettingsResponse = Json<operations["PaleeWeb.AdminAiSettingsController.show"]["responses"][200]>;

export type ScalingSuggestion = components["schemas"]["ScalingSuggestion"];
export type ScalingSuggestionItem = components["schemas"]["ScalingSuggestionItem"];
export type ScalingChange = ScalingSuggestionItem["change"];
export type ApproveScalingRequest = components["schemas"]["ScalingSuggestionApproveRequest"];
export type MyWorkoutScaling = NonNullable<MemberResponse["scaling"]>;
export type GymAiSettings = components["schemas"]["GymAiSettings"];
export type GymAiSettingsUpdate = components["schemas"]["GymAiSettingsUpdate"];

export const SCALING_QUEUE_KEY = ["staff", "scaling-suggestions"] as const;
export const AI_SETTINGS_KEY = ["admin", "ai-settings"] as const;
export const myScalingKey = (workoutId: string) => ["me", "workouts", workoutId, "scaling"] as const;

export async function fetchScalingQueue(token: string) {
  const response = await apiRequest<QueueResponse>("/staff/scaling-suggestions", { token });
  return response.suggestions ?? [];
}

export async function approveScalingSuggestion(token: string, id: string, body: ApproveScalingRequest) {
  const response = await apiRequest<SuggestionResponse>(`/staff/scaling-suggestions/${id}/approve`, {
    method: "POST",
    token,
    body,
  });
  return response.suggestion;
}

export async function dismissScalingSuggestion(token: string, id: string) {
  const response = await apiRequest<SuggestionResponse>(`/staff/scaling-suggestions/${id}/dismiss`, {
    method: "POST",
    token,
  });
  return response.suggestion;
}

/** The coach-approved adaptation of a workout for the signed-in member, or null. */
export async function fetchMyWorkoutScaling(token: string, workoutId: string) {
  const response = await apiRequest<MemberResponse>(`/me/workouts/${workoutId}/scaling`, { token });
  return response.scaling ?? null;
}

export async function fetchAiSettings(token: string) {
  const response = await apiRequest<SettingsResponse>("/admin/ai-settings", { token });
  return response.ai_settings;
}

export async function updateAiSettings(token: string, body: GymAiSettingsUpdate) {
  const response = await apiRequest<SettingsResponse>("/admin/ai-settings", { method: "PUT", token, body });
  return response.ai_settings;
}
