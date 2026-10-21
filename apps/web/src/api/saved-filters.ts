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

export type SavedFilter = SavedFilters["saved"][number];

/** Saves a named combination («ΣΚ κοντά»); the same name replaces it. */
export async function saveNamedFilter(token: string, surface: FilterSurface, name: string, params: Record<string, unknown>) {
  return apiRequest<SavedFilters>(`/me/filters/${surface}`, {
    method: "POST",
    token,
    body: { name, params },
  });
}

export async function deleteSavedFilter(token: string, surface: FilterSurface, id: string) {
  return apiRequest<SavedFilters>(`/me/filters/${surface}/${encodeURIComponent(id)}`, { method: "DELETE", token });
}

/** Γύρω μου only (ADR-154): a daily notification when something new matches. */
export async function setSavedFilterAlert(token: string, surface: FilterSurface, id: string, enabled: boolean) {
  return apiRequest<SavedFilters>(`/me/filters/${surface}/${encodeURIComponent(id)}/alert`, {
    method: "PUT",
    token,
    body: { enabled },
  });
}
