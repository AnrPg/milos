import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Ημερολόγιο › Ευεξία (ADR-159): water, sleep, meals and Λιγούρα, the
 * member's own targets and tile order, the coaches' plans as hand portions,
 * and the health-data consent every write needs.
 */
export type WellnessOverview = components["schemas"]["WellnessOverview"];
export type WellnessDay = WellnessOverview["days"][number];
export type WellnessEntry = WellnessOverview["entries"][number];
export type WellnessKind = WellnessEntry["kind"];
export type Craving = WellnessOverview["cravings"][number];
export type CravingTrigger = Craving["triggers"][number];
export type CravingOutcome = NonNullable<Craving["outcome"]>;
export type WellnessPreferences = WellnessOverview["preferences"];
export type WellnessItem = WellnessPreferences["item_order"][number];
export type WellnessPlan = WellnessOverview["plans"][number];
export type MealSlot = WellnessPlan["meal_slots"][number];
export type MealPhoto = WellnessOverview["photos"][string];
export type WellnessEntryRequest = components["schemas"]["WellnessEntryRequest"];
export type WellnessEntryChange = components["schemas"]["WellnessEntryChangeRequest"];
export type CravingRequest = components["schemas"]["CravingRequest"];
export type WellnessPreferencesRequest = components["schemas"]["WellnessPreferencesRequest"];
export type WellnessExport = components["schemas"]["WellnessExport"];
export type MediaUpload = components["schemas"]["MediaUpload"];
export type WellnessSection = "wellness" | "cravings";

export const WELLNESS_KEY = ["my", "wellness"] as const;

export const WELLNESS_ITEMS: WellnessItem[] = ["water", "sleep", "meals", "plan", "mood"];
export const CRAVING_TRIGGERS: CravingTrigger[] = ["stress", "fatigue", "boredom", "social", "hunger", "other"];
export const CRAVING_OUTCOMES: CravingOutcome[] = ["resisted", "ate_off_plan", "ongoing"];
export const PORTION_KEYS = ["protein", "carbs", "veg", "fat"] as const;
export type PortionKey = (typeof PORTION_KEYS)[number];

/** The member's zone, so entries count on the day they were in. */
export function currentZone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

export function fetchWellness(token: string, from: string, to: string) {
  return apiRequest<WellnessOverview>(`/me/wellness?from=${from}&to=${to}`, { token });
}

export async function logWellnessEntry(token: string, body: WellnessEntryRequest) {
  const data = await apiRequest<{ entry: WellnessEntry }>("/me/wellness/entries", {
    method: "POST",
    token,
    body: { occurred_tz: currentZone(), ...body },
  });
  return data.entry;
}

export async function updateWellnessEntry(token: string, id: string, body: WellnessEntryChange) {
  const data = await apiRequest<{ entry: WellnessEntry }>(`/me/wellness/entries/${id}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.entry;
}

export function deleteWellnessEntry(token: string, id: string) {
  return apiRequest<void>(`/me/wellness/entries/${id}`, { method: "DELETE", token });
}

export async function logCraving(token: string, body: CravingRequest) {
  const data = await apiRequest<{ craving: Craving }>("/me/wellness/cravings", {
    method: "POST",
    token,
    body: { occurred_tz: currentZone(), ...body },
  });
  return data.craving;
}

export async function updateCraving(token: string, id: string, body: CravingRequest) {
  const data = await apiRequest<{ craving: Craving }>(`/me/wellness/cravings/${id}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.craving;
}

export function deleteCraving(token: string, id: string) {
  return apiRequest<void>(`/me/wellness/cravings/${id}`, { method: "DELETE", token });
}

/** The preferences alone (no consent needed), e.g. `hide_macros` for the coach's plan (ADR-194). */
export const WELLNESS_PREFERENCES_KEY = [...WELLNESS_KEY, "preferences"] as const;

export async function fetchWellnessPreferences(token: string) {
  const data = await apiRequest<{ preferences: WellnessPreferences }>("/me/wellness/preferences", { token });
  return data.preferences;
}

export async function updateWellnessPreferences(token: string, body: WellnessPreferencesRequest) {
  const data = await apiRequest<{ preferences: WellnessPreferences }>("/me/wellness/preferences", {
    method: "PUT",
    token,
    body,
  });
  return data.preferences;
}

export function requestMealPhotoUpload(token: string, body: { content_type: string; byte_size: number }) {
  return apiRequest<MediaUpload>("/me/wellness/meal-photos", { method: "POST", token, body });
}

export function exportWellness(token: string, sections: WellnessSection[]) {
  return apiRequest<WellnessExport>(`/me/wellness/export?sections=${sections.join(",")}`, { token });
}

export function eraseWellness(token: string, sections: WellnessSection[]) {
  return apiRequest<{ erased: Record<string, number> }>(`/me/wellness?sections=${sections.join(",")}`, {
    method: "DELETE",
    token,
  });
}

/** M10's consent (Σώμα owns it); Ευεξία needs `health_data`. */
export function grantHealthDataConsent(token: string) {
  return apiRequest<unknown>("/me/body/consents/health_data", { method: "PUT", token, body: {} });
}
