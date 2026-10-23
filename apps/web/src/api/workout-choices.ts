import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// The class form's WOD picker: suggestions for a class and a paged library
// search, so a library of thousands is never loaded whole.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;

export type WorkoutChoicePage = Json<operations["PaleeWeb.AdminWorkoutChoiceController.search"]["responses"][200]>;
export type SuggestedWorkoutChoices = Json<
  operations["PaleeWeb.AdminWorkoutChoiceController.suggested"]["responses"][200]
>;
export type WorkoutChoice = WorkoutChoicePage["workouts"][number];

export type WorkoutChoiceSearch = {
  q?: string;
  type?: string;
  folderId?: string;
  offset?: number;
  limit?: number;
};

export function searchWorkoutChoices(token: string, params: WorkoutChoiceSearch) {
  const search = new URLSearchParams();
  if (params.q?.trim()) search.set("q", params.q.trim());
  if (params.type) search.set("type", params.type);
  if (params.folderId) search.set("folder_id", params.folderId);
  if (params.offset) search.set("offset", String(params.offset));
  if (params.limit) search.set("limit", String(params.limit));
  const query = search.toString();
  return apiRequest<WorkoutChoicePage>(`/admin/workouts/choices${query ? `?${query}` : ""}`, { token });
}

export function fetchSuggestedWorkoutChoices(token: string, params: { date: string; classTypeId?: string | null }) {
  const search = new URLSearchParams({ date: params.date });
  if (params.classTypeId) search.set("class_type_id", params.classTypeId);
  return apiRequest<SuggestedWorkoutChoices>(`/admin/workouts/choices/suggested?${search.toString()}`, { token });
}
