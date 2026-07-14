import { apiRequest } from "@/api/client";

export type AnalyticsSummary = Record<string, unknown>;

export async function fetchAdminAnalyticsSummary(token: string, days = 30) {
  const params = new URLSearchParams({ days: String(days) });
  return apiRequest<AnalyticsSummary>(`/admin/analytics/summary?${params.toString()}`, { token });
}
