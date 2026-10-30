import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type MyInjuriesResponse =
  operations["PaleeWeb.WellbeingController.index"]["responses"][200]["content"]["application/json"];
type ReportInjuryResponse =
  operations["PaleeWeb.WellbeingController.create"]["responses"][201]["content"]["application/json"];
type HealMyInjuryResponse =
  operations["PaleeWeb.WellbeingController.heal"]["responses"][200]["content"]["application/json"];
type AdminInjuriesResponse =
  operations["PaleeWeb.AdminWellbeingController.index"]["responses"][200]["content"]["application/json"];
type AdminReportInjuryResponse =
  operations["PaleeWeb.AdminWellbeingController.create"]["responses"][201]["content"]["application/json"];
type AdminHealInjuryResponse =
  operations["PaleeWeb.AdminWellbeingController.heal"]["responses"][200]["content"]["application/json"];

type InjuryAccessLogResponse =
  operations["PaleeWeb.WellbeingController.access_log"]["responses"][200]["content"]["application/json"];

export type InjuryRecord = MyInjuriesResponse["injuries"][number];
/** ADR-286: one staff read of the member's injuries. */
export type InjuryAccessEntry = InjuryAccessLogResponse["entries"][number];
export const INJURY_ACCESS_LOG_KEY = ["my", "wellbeing", "injuries", "access-log"] as const;
export type ReportInjuryRequest =
  operations["PaleeWeb.WellbeingController.create"]["requestBody"]["content"]["application/json"];
export type AdminInjuryFilters = NonNullable<
  operations["PaleeWeb.AdminWellbeingController.index"]["parameters"]["query"]
>;
export type AdminReportInjuryRequest =
  operations["PaleeWeb.AdminWellbeingController.create"]["requestBody"]["content"]["application/json"];

export async function fetchMyInjuries(token: string) {
  return apiRequest<MyInjuriesResponse>("/wellbeing/injuries", { token });
}

export async function fetchMyInjuryAccessLog(token: string) {
  return (await apiRequest<InjuryAccessLogResponse>("/wellbeing/injuries/access-log", { token })).entries;
}

/** ADR-286: «Να το δει το box μου» on one of the member's own injuries. */
export async function setMyInjurySharing(token: string, injuryId: string, shared: boolean) {
  return apiRequest<HealMyInjuryResponse>(`/wellbeing/injuries/${injuryId}/sharing`, {
    method: "PUT",
    token,
    body: { shared_with_box: shared },
  });
}

export async function reportInjury(token: string, body: ReportInjuryRequest) {
  return apiRequest<ReportInjuryResponse>("/wellbeing/injuries", {
    method: "POST",
    token,
    body,
  });
}

export async function markMyInjuryHealed(token: string, injuryId: string) {
  return apiRequest<HealMyInjuryResponse>(`/wellbeing/injuries/${injuryId}/heal`, {
    method: "PATCH",
    token,
    body: {},
  });
}

export async function fetchAdminInjuries(token: string, filters: AdminInjuryFilters = {}) {
  const params = new URLSearchParams();
  Object.entries(filters).forEach(([key, value]) => {
    if (value !== undefined) params.set(key, String(value));
  });
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return apiRequest<AdminInjuriesResponse>(`/admin/wellbeing/injuries${suffix}`, { token });
}

export async function adminReportInjury(token: string, userId: string, body: AdminReportInjuryRequest) {
  return apiRequest<AdminReportInjuryResponse>(`/admin/wellbeing/users/${userId}/injuries`, {
    method: "POST",
    token,
    body,
  });
}

export async function adminMarkInjuryHealed(token: string, injuryId: string) {
  return apiRequest<AdminHealInjuryResponse>(`/admin/wellbeing/injuries/${injuryId}/heal`, {
    method: "PATCH",
    token,
    body: {},
  });
}

// ADR-140 §2 Πώς νιώθω: immutable, timestamped check-ins.
type CheckInTimelineResponse =
  operations["PaleeWeb.CheckInController.index"]["responses"][200]["content"]["application/json"];
type SubmitCheckInResponse =
  operations["PaleeWeb.CheckInController.create"]["responses"][201]["content"]["application/json"];

export type CheckInTimeline = CheckInTimelineResponse;
export type CheckInRecord = CheckInTimelineResponse["check_ins"][number];
export type CheckInQuestion = CheckInTimelineResponse["questions"][number];
export type SubmitCheckInRequest =
  operations["PaleeWeb.CheckInController.create"]["requestBody"]["content"]["application/json"];

export async function fetchMyCheckIns(token: string, window: { from: string; to: string }) {
  const params = new URLSearchParams(window);
  return apiRequest<CheckInTimelineResponse>(`/wellbeing/check-ins?${params.toString()}`, { token });
}

export async function submitCheckIn(token: string, body: SubmitCheckInRequest) {
  return apiRequest<SubmitCheckInResponse>("/wellbeing/check-ins", { method: "POST", token, body });
}

export async function deleteMyCheckIn(token: string, checkInId: string) {
  return apiRequest<void>(`/wellbeing/check-ins/${checkInId}`, { method: "DELETE", token });
}

// ADR-140 §3: injury updates and reopenings are timestamped timeline events.
type UpdateInjuryResponse =
  operations["PaleeWeb.WellbeingController.update"]["responses"][200]["content"]["application/json"];
export type InjuryUpdateRequest =
  operations["PaleeWeb.WellbeingController.update"]["requestBody"]["content"]["application/json"];

export async function updateMyInjury(token: string, injuryId: string, body: InjuryUpdateRequest) {
  return apiRequest<UpdateInjuryResponse>(`/wellbeing/injuries/${injuryId}`, { method: "PATCH", token, body });
}

export async function reopenMyInjury(token: string, injuryId: string) {
  return apiRequest<UpdateInjuryResponse>(`/wellbeing/injuries/${injuryId}/reopen`, { method: "POST", token, body: {} });
}

export async function adminUpdateInjury(token: string, injuryId: string, body: InjuryUpdateRequest) {
  return apiRequest<UpdateInjuryResponse>(`/admin/wellbeing/injuries/${injuryId}`, { method: "PATCH", token, body });
}

export async function adminReopenInjury(token: string, injuryId: string) {
  return apiRequest<UpdateInjuryResponse>(`/admin/wellbeing/injuries/${injuryId}/reopen`, {
    method: "POST",
    token,
    body: {},
  });
}
