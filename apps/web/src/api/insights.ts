import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Πρόοδος › Insights (ADR-166): the member's own findings from sleep, water,
 * cravings, sessions and PRs, computed nightly, at most a few at a time,
 * each dismissible until the finding changes. Account-level.
 */
export type MyInsights = components["schemas"]["MyInsights"];
export type Insight = MyInsights["insights"][number];
export type InsightParams = components["schemas"]["InsightParams"];

export const myInsightsKey = (token: string | null) => ["me", "insights", token] as const;

export function fetchMyInsights(token: string) {
  return apiRequest<MyInsights>("/me/insights", { token, scope: "account" });
}

export function dismissInsight(token: string, rule: Insight["rule"]) {
  return apiRequest<MyInsights>(`/me/insights/${encodeURIComponent(rule)}/dismiss`, {
    token,
    scope: "account",
    method: "POST",
  });
}

export function restoreInsights(token: string) {
  return apiRequest<MyInsights>("/me/insights/restore", { token, scope: "account", method: "POST" });
}
