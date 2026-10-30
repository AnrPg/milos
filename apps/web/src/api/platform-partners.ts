import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Platform console › Συναθλητές (ADR-280 §5): the Palee check of people who
 * came with sponsors, the reports on people in Partners, and the anonymous
 * counters of the «Κλείστε μαζί» suggestions. Vendors only.
 */
export type PlatformVerifications = components["schemas"]["PlatformPartnerVerifications"];
export type PlatformVerificationItem = components["schemas"]["PlatformPartnerVerificationItem"];
export type PlatformVerification = components["schemas"]["PlatformPartnerVerification"];
export type PlatformVerificationStatus = PlatformVerification["status"];
export type PlatformVerificationDecision = components["schemas"]["PlatformPartnerVerificationDecision"];
export type PlatformVerificationDecided = components["schemas"]["PlatformPartnerVerificationDecided"];
export type PlatformReports = components["schemas"]["PlatformPartnerReports"];
export type PlatformReport = components["schemas"]["PlatformPartnerReport"];
export type PlatformReportReason = PlatformReport["reason"];
export type PlatformReportStatus = PlatformReport["status"];
export type PlatformReportDecisionRequest = components["schemas"]["PlatformPartnerReportDecisionRequest"];
export type PlatformReportDecision = components["schemas"]["PlatformPartnerReportDecision"];
export type SuggestionStats = components["schemas"]["PartnerSuggestionStats"];

export const PLATFORM_PARTNERS_KEY = ["platform", "partners"] as const;
export const PLATFORM_VERIFICATIONS_KEY = [...PLATFORM_PARTNERS_KEY, "verifications"] as const;
export const PLATFORM_REPORTS_KEY = [...PLATFORM_PARTNERS_KEY, "reports"] as const;
export const SUGGESTION_STATS_KEY = [...PLATFORM_PARTNERS_KEY, "suggestion-stats"] as const;

export const REPORT_REASONS: PlatformReportReason[] = ["unsafe", "fake", "minor", "harassment", "other"];
/** The longest decision reason or note the API takes. */
export const DECISION_TEXT_MAX = 500;

export function fetchPlatformVerifications(token: string, status: PlatformVerificationStatus = "in_review") {
  return apiRequest<PlatformVerifications>(`/platform/partner-verifications?status=${encodeURIComponent(status)}`, {
    token,
    scope: "account",
  });
}

/** One request, with a selfie link that lives 5 minutes. */
export function fetchPlatformVerification(token: string, id: string) {
  return apiRequest<PlatformVerification>(`/platform/partner-verifications/${encodeURIComponent(id)}`, { token, scope: "account" });
}

export function decidePlatformVerification(token: string, id: string, body: PlatformVerificationDecision) {
  return apiRequest<PlatformVerificationDecided>(`/platform/partner-verifications/${encodeURIComponent(id)}/decision`, {
    method: "POST",
    token,
    scope: "account",
    body,
  });
}

export function fetchPlatformReports(token: string, status: PlatformReportStatus = "open") {
  return apiRequest<PlatformReports>(`/platform/partner-reports?status=${encodeURIComponent(status)}`, { token, scope: "account" });
}

/** A decision on one report closes every open report on the same person. */
export function decidePlatformReport(token: string, id: string, body: PlatformReportDecisionRequest) {
  return apiRequest<PlatformReportDecision>(`/platform/partner-reports/${encodeURIComponent(id)}/decision`, {
    method: "POST",
    token,
    scope: "account",
    body,
  });
}

export function fetchSuggestionStats(token: string) {
  return apiRequest<SuggestionStats>("/platform/partner-suggestion-stats", { token, scope: "account" });
}

export type ReportGroup = { target: PlatformReport["target"]; reports: PlatformReport[] };

/** Reports gathered per reported person, the person with the most first, then the oldest report first. */
export function groupReportsByPerson(reports: PlatformReport[]): ReportGroup[] {
  const groups = new Map<string, ReportGroup>();
  for (const report of reports) {
    const group = groups.get(report.target.id) ?? { target: report.target, reports: [] };
    group.reports.push(report);
    groups.set(report.target.id, group);
  }
  const oldest = (group: ReportGroup) => Math.min(...group.reports.map((report) => Date.parse(report.created_at)));
  return [...groups.values()].sort((a, b) => b.reports.length - a.reports.length || oldest(a) - oldest(b));
}

/** The 30 days' counters summed, and the share of shown suggestions that were proposed. */
export function suggestionTotals(stats: SuggestionStats) {
  const totals = stats.days.reduce(
    (sum, day) => ({
      shown: sum.shown + day.shown,
      proposed: sum.proposed + day.proposed,
      booked_together: sum.booked_together + day.booked_together,
      feedback: sum.feedback + day.feedback,
    }),
    { shown: 0, proposed: 0, booked_together: 0, feedback: 0 },
  );
  const proposedShare = totals.shown > 0 ? Math.round((totals.proposed / totals.shown) * 100) : null;
  return { ...totals, proposedShare };
}
