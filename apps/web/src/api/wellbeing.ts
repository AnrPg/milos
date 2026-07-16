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
