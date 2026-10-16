import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type MyInjuriesResponse =
  operations["MilosTrainingWeb.WellbeingController.index"]["responses"][200]["content"]["application/json"];
type ReportInjuryResponse =
  operations["MilosTrainingWeb.WellbeingController.create"]["responses"][201]["content"]["application/json"];
type HealMyInjuryResponse =
  operations["MilosTrainingWeb.WellbeingController.heal"]["responses"][200]["content"]["application/json"];
type AdminInjuriesResponse =
  operations["MilosTrainingWeb.AdminWellbeingController.index"]["responses"][200]["content"]["application/json"];
type AdminReportInjuryResponse =
  operations["MilosTrainingWeb.AdminWellbeingController.create"]["responses"][201]["content"]["application/json"];
type AdminHealInjuryResponse =
  operations["MilosTrainingWeb.AdminWellbeingController.heal"]["responses"][200]["content"]["application/json"];

export type InjuryRecord = MyInjuriesResponse["injuries"][number];
export type ReportInjuryRequest =
  operations["MilosTrainingWeb.WellbeingController.create"]["requestBody"]["content"]["application/json"];
export type AdminInjuryFilters = NonNullable<
  operations["MilosTrainingWeb.AdminWellbeingController.index"]["parameters"]["query"]
>;
export type AdminReportInjuryRequest =
  operations["MilosTrainingWeb.AdminWellbeingController.create"]["requestBody"]["content"]["application/json"];

export async function fetchMyInjuries(token: string) {
  return apiRequest<MyInjuriesResponse>("/wellbeing/injuries", { token });
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
  operations["MilosTrainingWeb.CheckInController.index"]["responses"][200]["content"]["application/json"];
type SubmitCheckInResponse =
  operations["MilosTrainingWeb.CheckInController.create"]["responses"][201]["content"]["application/json"];

export type CheckInTimeline = CheckInTimelineResponse;
export type CheckInRecord = CheckInTimelineResponse["check_ins"][number];
export type CheckInQuestion = CheckInTimelineResponse["questions"][number];
export type SubmitCheckInRequest =
  operations["MilosTrainingWeb.CheckInController.create"]["requestBody"]["content"]["application/json"];

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
  operations["MilosTrainingWeb.WellbeingController.update"]["responses"][200]["content"]["application/json"];
export type InjuryUpdateRequest =
  operations["MilosTrainingWeb.WellbeingController.update"]["requestBody"]["content"]["application/json"];

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
