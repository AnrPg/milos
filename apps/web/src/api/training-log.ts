import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type TrainingLogPage = components["schemas"]["TrainingLogPage"];
export type TrainingLogEntry = TrainingLogPage["entries"][number];
export type TrainingLogKind = "workouts" | "classes";

const PAGE_SIZE = 10;

function query(kind: TrainingLogKind, offset: number) {
  return new URLSearchParams({ kind, offset: String(offset), limit: String(PAGE_SIZE) }).toString();
}

/** The signed-in user's training log (own profile). */
export function fetchMyTrainingLog(token: string, kind: TrainingLogKind, offset: number) {
  return apiRequest<TrainingLogPage>(`/me/history?${query(kind, offset)}`, { token });
}

/** A user's training log, for coaches and admins. */
export function fetchUserTrainingLog(token: string, userId: string, kind: TrainingLogKind, offset: number) {
  return apiRequest<TrainingLogPage>(`/admin/users/${userId}/history?${query(kind, offset)}`, { token });
}
