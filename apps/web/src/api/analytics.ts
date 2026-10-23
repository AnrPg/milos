import { apiRequest } from "@/api/client";

export type AnalyticsSummary = Record<string, unknown>;

export async function fetchAdminAnalyticsSummary(token: string, days = 30, locationIds?: string) {
  const params = new URLSearchParams({ days: String(days) });
  if (locationIds) params.set("location_ids", locationIds);
  return apiRequest<AnalyticsSummary>(`/admin/analytics/summary?${params.toString()}`, { token });
}
