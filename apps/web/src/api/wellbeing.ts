import { apiRequest } from "@/api/client";

export type InjuryRecord = Record<string, unknown>;

export async function fetchMyInjuries(token: string) {
  return apiRequest<{ injuries: InjuryRecord[] }>("/wellbeing/injuries", { token });
}

export async function reportInjury(token: string, body: InjuryRecord) {
  return apiRequest<{ injury: InjuryRecord }>("/wellbeing/injuries", {
    method: "POST",
    token,
    body,
  });
}

export async function markMyInjuryHealed(token: string, injuryId: string) {
  return apiRequest<{ injury: InjuryRecord }>(`/wellbeing/injuries/${injuryId}/heal`, {
    method: "PATCH",
    token,
    body: {},
  });
}

export async function fetchAdminInjuries(token: string, filters: Record<string, string> = {}) {
  const params = new URLSearchParams(filters);
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return apiRequest<{ injuries: InjuryRecord[] }>(`/admin/wellbeing/injuries${suffix}`, { token });
}

export async function adminReportInjury(token: string, userId: string, body: InjuryRecord) {
  return apiRequest<{ injury: InjuryRecord }>(`/admin/wellbeing/users/${userId}/injuries`, {
    method: "POST",
    token,
    body,
  });
}

export async function adminMarkInjuryHealed(token: string, injuryId: string) {
  return apiRequest<{ injury: InjuryRecord }>(`/admin/wellbeing/injuries/${injuryId}/heal`, {
    method: "PATCH",
    token,
    body: {},
  });
}
