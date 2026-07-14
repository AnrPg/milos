import { apiRequest } from "@/api/client";

export type AthleteSummary = {
  id: string;
  nickname: string;
  role: string;
};

export type AdminAthleteNote = {
  id: string;
  admin_id: string;
  athlete_id: string;
  body: string;
  inserted_at: string;
};

export type AthleteDrillDown = Record<string, unknown>;

export type AttendanceRecord = {
  id: string;
  scheduled_class_id: string;
  user_id: string;
  status: string;
  marked_by_id: string;
  marked_at: string;
  notes?: string;
};

export async function fetchAthletes(token: string, query?: string) {
  const suffix = query ? `?q=${encodeURIComponent(query)}` : "";
  return apiRequest<{ athletes: AthleteSummary[] }>(`/admin/athletes${suffix}`, { token });
}

export async function fetchAthleteDrillDown(
  token: string,
  athleteId: string,
  params?: { start_date?: string; end_date?: string },
) {
  const qs = params
    ? "?" + new URLSearchParams(Object.entries(params).filter(([, v]) => Boolean(v)) as [string, string][]).toString()
    : "";
  return apiRequest<{ drill_down: AthleteDrillDown }>(`/admin/athletes/${athleteId}/drill-down${qs}`, { token });
}

export async function writeAthleteNote(token: string, athleteId: string, body: string) {
  return apiRequest<{ note: AdminAthleteNote }>(`/admin/athletes/${athleteId}/notes`, {
    method: "POST",
    token,
    body: { body },
  });
}

export async function adminRecordAttendance(
  token: string,
  slotId: string,
  userId: string,
  params: { status?: string; notes?: string } = {},
) {
  return apiRequest<{ attendance: AttendanceRecord }>(
    `/admin/schedule/slots/${slotId}/attendance/${userId}`,
    { method: "POST", token, body: params },
  );
}
