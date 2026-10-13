import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type TrainingHistoryPage = components["schemas"]["TrainingHistoryPage"];
export type TrainingHistoryEntry = TrainingHistoryPage["entries"][number];
export type TrainingHistoryKind = "workouts" | "classes";

const PAGE_SIZE = 10;

function query(kind: TrainingHistoryKind, offset: number) {
  return new URLSearchParams({ kind, offset: String(offset), limit: String(PAGE_SIZE) }).toString();
}

/** The signed-in user's training log (own profile). */
export function fetchMyTrainingHistory(token: string, kind: TrainingHistoryKind, offset: number) {
  return apiRequest<TrainingHistoryPage>(`/me/history?${query(kind, offset)}`, { token });
}

/** A user's training log, for coaches and admins. */
export function fetchUserTrainingHistory(token: string, userId: string, kind: TrainingHistoryKind, offset: number) {
  return apiRequest<TrainingHistoryPage>(`/admin/users/${userId}/history?${query(kind, offset)}`, { token });
}
