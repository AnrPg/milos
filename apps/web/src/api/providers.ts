import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Everyone who trains you (ADR-162, vision §7.10): the gyms and independent
 * coaches you belong to, the one Box shows (remembered on your account), the
 * providers you left, and today merged across all of them.
 */
export type MyProviders = components["schemas"]["MyProviders"];
export type Provider = MyProviders["providers"][number];
export type FormerProvider = MyProviders["former"][number];
export type MyToday = components["schemas"]["MyToday"];
export type TodayItem = MyToday["items"][number];
export type EntrySource = components["schemas"]["EntrySource"];

export const MY_PROVIDERS_KEY = ["my", "providers"] as const;
export const MY_TODAY_KEY = ["my", "today"] as const;

export function fetchMyProviders(token: string) {
  return apiRequest<MyProviders>("/me/providers", { token, scope: "account" });
}

export function selectProvider(token: string, organizationId: string) {
  return apiRequest<MyProviders>("/me/providers/selected", {
    method: "PUT",
    token,
    scope: "account",
    body: { organization_id: organizationId },
  });
}

/** Today from every provider, in the member's own day and zone. */
export function fetchMyToday(token: string, date: string, timezone: string) {
  const query = new URLSearchParams({ date, timezone });
  return apiRequest<MyToday>(`/me/today?${query}`, { token, scope: "account" });
}
