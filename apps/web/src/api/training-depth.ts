import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { ProgressRange, SourceToken } from "@/api/account-training";

/**
 * The Πρόοδος depth sections (ADR-165): muscle coverage summary, qualities
 * radar and training load. The member's own across every provider (account
 * read model, the Πρόοδος range and sources), and a coach's view of one
 * client from the entries the client shares with the gym.
 */
export type MyTrainingDepth = components["schemas"]["MyTrainingDepth"];
export type ClientTrainingDepth = components["schemas"]["ClientTrainingDepth"];
export type TrainingDepth = MyTrainingDepth | ClientTrainingDepth;
export type DepthCoverage = TrainingDepth["coverage"];
export type DepthQualities = TrainingDepth["qualities"];
export type DepthLoad = TrainingDepth["load"];

export const COACH_DEPTH_RANGES = ["4w", "12w", "6m"] as const satisfies readonly ProgressRange[];
export type CoachDepthRange = (typeof COACH_DEPTH_RANGES)[number];

export const myTrainingDepthKey = (range: ProgressRange, sources: readonly SourceToken[]) =>
  ["me", "progress-depth", range, [...sources].sort().join(",")] as const;

export const clientTrainingDepthKey = (userId: string, range: CoachDepthRange) =>
  ["staff", "clients", userId, "progress-depth", range] as const;

export function fetchMyTrainingDepth(token: string, range: ProgressRange, sources: readonly SourceToken[]) {
  const query = new URLSearchParams({ range });
  if (sources.length) query.set("sources", sources.join(","));
  return apiRequest<MyTrainingDepth>(`/me/progress/depth?${query.toString()}`, { token, scope: "account" });
}

/** Tenant-scoped: the gym the coach is working in. */
export function fetchClientTrainingDepth(token: string, userId: string, range: CoachDepthRange) {
  return apiRequest<ClientTrainingDepth>(
    `/staff/clients/${encodeURIComponent(userId)}/progress-depth?range=${encodeURIComponent(range)}`,
    { token },
  );
}
