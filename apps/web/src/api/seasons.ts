import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Seasons (ADR-167, P3-M5): a gym sells a fixed-length programme with dates
 * and places. A member asks for a place and staff confirm it (no card
 * processor); confirmation grants the package, adds the member to the
 * season's channel and schedules the programme. Member calls go through the
 * selected gym (`/me/seasons`); staff calls through `/admin`.
 */
export type MemberSeason = components["schemas"]["MemberSeason"];
export type SeasonEnrollmentStatus = NonNullable<MemberSeason["mine"]>["status"];
export type SeasonStatus = MemberSeason["status"];
export type StaffSeason = components["schemas"]["StaffSeason"];
export type StaffSeasonDetail = components["schemas"]["StaffSeasonDetail"];
export type StaffSeasonEnrollment = StaffSeasonDetail["enrollments"][number];
export type SeasonCoachCandidate = components["schemas"]["StaffSeasonList"]["coach_candidates"][number];
export type SeasonCreate = components["schemas"]["SeasonCreate"];
export type SeasonUpdate = components["schemas"]["SeasonUpdate"];
export type SeasonProgrammeItem = StaffSeasonDetail["programme"][number];

export const MY_SEASONS_KEY = ["seasons", "mine"] as const;
export const STAFF_SEASONS_KEY = ["admin", "seasons"] as const;
export const staffSeasonKey = (id: string) => ["admin", "seasons", id] as const;

const id = (value: string) => encodeURIComponent(value);

// Member ------------------------------------------------------------------

export async function fetchMySeasons(token: string) {
  const data = await apiRequest<{ seasons?: MemberSeason[] }>("/me/seasons", { token });
  return data.seasons ?? [];
}

export async function requestSeasonPlace(token: string, seasonId: string) {
  const data = await apiRequest<{ season: MemberSeason }>(`/me/seasons/${id(seasonId)}/request`, {
    method: "POST",
    token,
  });
  return data.season;
}

export async function cancelSeasonRequest(token: string, seasonId: string) {
  const data = await apiRequest<{ season: MemberSeason }>(`/me/seasons/${id(seasonId)}/cancel`, {
    method: "POST",
    token,
  });
  return data.season;
}

// Staff -------------------------------------------------------------------

export async function fetchStaffSeasons(token: string) {
  const data = await apiRequest<{ seasons?: StaffSeason[]; coach_candidates?: SeasonCoachCandidate[] }>(
    "/admin/seasons",
    { token },
  );
  return { seasons: data.seasons ?? [], coachCandidates: data.coach_candidates ?? [] };
}

export async function fetchStaffSeason(token: string, seasonId: string) {
  const data = await apiRequest<{ season: StaffSeasonDetail }>(`/admin/seasons/${id(seasonId)}`, { token });
  return data.season;
}

export async function createSeason(token: string, body: SeasonCreate) {
  const data = await apiRequest<{ season: StaffSeasonDetail }>("/admin/seasons", { method: "POST", token, body });
  return data.season;
}

export async function updateSeason(token: string, seasonId: string, body: SeasonUpdate) {
  const data = await apiRequest<{ season: StaffSeasonDetail }>(`/admin/seasons/${id(seasonId)}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.season;
}

export type EnrollmentAction = "confirm" | "decline" | "remove";

export async function actOnSeasonEnrollment(
  token: string,
  enrollmentId: string,
  action: EnrollmentAction,
  reason?: string,
) {
  const data = await apiRequest<{ season: StaffSeasonDetail }>(
    `/admin/season-enrollments/${id(enrollmentId)}/${action}`,
    { method: "POST", token, body: action === "decline" ? { reason: reason?.trim() || null } : undefined },
  );
  return data.season;
}

// Pure helpers ------------------------------------------------------------

/** What a member may do with a season right now. */
export function memberSeasonAction(season: Pick<MemberSeason, "status" | "mine">): "request" | "cancel" | null {
  const mine = season.mine?.status;
  if (mine === "requested" || mine === "waitlisted") return "cancel";
  if (mine === "active" || mine === "completed") return null;
  return season.status === "published" || season.status === "running" ? "request" : null;
}

/** Programme rows as the API wants them: whole days inside the season, one workout each. */
export function cleanProgramme(rows: Array<{ day: number | string; workout_id: string }>, weeks: number) {
  const max = Math.max(1, Math.floor(weeks)) * 7;
  const seen = new Set<string>();
  return rows
    .map((row) => ({ day: Math.floor(Number(row.day)), workout_id: row.workout_id }))
    .filter((row) => row.workout_id && Number.isFinite(row.day) && row.day >= 0 && row.day < max)
    .filter((row) => {
      const key = `${row.day}:${row.workout_id}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((a, b) => a.day - b.day);
}

/** The calendar date of programme day `day` (day 0 is the start), as YYYY-MM-DD. */
export function programmeDate(startsOn: string, day: number) {
  const date = new Date(`${startsOn}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return "";
  date.setUTCDate(date.getUTCDate() + day);
  return date.toISOString().slice(0, 10);
}
