import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

// ADR-151: a person's remembered filters per list surface (account-level).
export type SavedFilters = components["schemas"]["SavedFilters"];
export type FilterSurface = SavedFilters["surface"];

export async function fetchSavedFilters(token: string, surface: FilterSurface) {
  return apiRequest<SavedFilters>(`/me/filters/${surface}`, { token });
}

export async function rememberFilters(token: string, surface: FilterSurface, params: Record<string, unknown>) {
  return apiRequest<SavedFilters>(`/me/filters/${surface}/last-used`, {
    method: "PUT",
    token,
    body: { params },
  });
}
