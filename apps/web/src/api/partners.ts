import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Partners (ADR-169): a training partner among the members of one club, with
 * an opt-in profile per club, a deck, mutual matches, the pair's own
 * conversation with «Κλείστε μαζί», the Ρυθμίσεις switch and blocked people.
 */
export type PartnersClubOverview = components["schemas"]["PartnersClubOverview"];
export type PartnerOptions = components["schemas"]["PartnerOptions"];
export type PartnerProfile = components["schemas"]["PartnerProfile"];
export type PartnerProfileRequest = components["schemas"]["PartnerProfileRequest"];
export type PartnerCard = components["schemas"]["PartnerCard"];
export type PartnerDeck = components["schemas"]["PartnerDeck"];
export type PartnerSwipeResponse = components["schemas"]["PartnerSwipeResponse"];
export type PartnerMatch = components["schemas"]["PartnerMatch"];
export type PartnerMessage = components["schemas"]["PartnerMessage"];
export type PartnerMessagePage = components["schemas"]["PartnerMessagePage"];
export type PartnerSession = components["schemas"]["PartnerSession"];
export type PartnerSessions = components["schemas"]["PartnerSessions"];
export type PartnerSettings = components["schemas"]["PartnerSettings"];
export type BlockedPerson = components["schemas"]["BlockedPeople"]["blocks"][number];
export type PartnerLevel = PartnerProfile["level"];
export type PartnerTime = PartnerProfile["times"][number];
export type PartnerGoal = PartnerProfile["goals"][number];
export type PartnerGender = NonNullable<PartnerProfile["gender"]>;
export type PartnerGenderPreference = PartnerProfile["gender_preference"];
export type SwipeDirection = PartnerSwipeResponse["direction"];
export type PartnerFilters = {
  time?: PartnerTime | null;
  level?: PartnerLevel | null;
  goal?: PartnerGoal | null;
  /** A discipline on the partner profile (ADR-197). */
  discipline?: string | null;
  /** Open clubs only, between people shown in Γύρω μου (ADR-197). */
  within_km?: number | null;
};

export const PARTNERS_KEY = ["my", "partners"] as const;
export const PARTNER_MATCHES_KEY = [...PARTNERS_KEY, "matches"] as const;
export const PARTNER_SETTINGS_KEY = [...PARTNERS_KEY, "settings"] as const;
export const BLOCKS_KEY = ["my", "blocks"] as const;

export const partnersClubKey = (clubId: string) => [...PARTNERS_KEY, "club", clubId] as const;
export const partnerDeckKey = (clubId: string, filters: PartnerFilters = {}) =>
  [
    ...PARTNERS_KEY,
    "club",
    clubId,
    "deck",
    filters.time ?? null,
    filters.level ?? null,
    filters.goal ?? null,
    filters.discipline ?? null,
    filters.within_km ?? null,
  ] as const;
export const partnerMessagesKey = (matchId: string) => [...PARTNER_MATCHES_KEY, matchId, "messages"] as const;
export const partnerSessionsKey = (matchId: string) => [...PARTNER_MATCHES_KEY, matchId, "sessions"] as const;

const id = (value: string) => encodeURIComponent(value);

function query(params: Record<string, string | null | undefined>) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([name, value]) => {
    if (value) search.set(name, value);
  });
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function fetchPartnersClub(token: string, clubId: string) {
  return apiRequest<PartnersClubOverview>(`/me/clubs/${id(clubId)}/partners`, { token });
}

export async function putPartnerProfile(token: string, clubId: string, body: PartnerProfileRequest) {
  return (await apiRequest<{ profile: PartnerProfile }>(`/me/clubs/${id(clubId)}/partners/profile`, { method: "PUT", token, body })).profile;
}

export function fetchPartnerDeck(token: string, clubId: string, filters: PartnerFilters = {}) {
  return apiRequest<PartnerDeck>(
    `/me/clubs/${id(clubId)}/partners/deck${query({
      time: filters.time,
      level: filters.level,
      goal: filters.goal,
      discipline: filters.discipline,
      within_km: filters.within_km ? String(filters.within_km) : null,
    })}`,
    { token },
  );
}

export function swipePartner(token: string, clubId: string, targetId: string, direction: SwipeDirection) {
  return apiRequest<PartnerSwipeResponse>(`/me/clubs/${id(clubId)}/partners/swipes`, {
    method: "POST",
    token,
    body: { target_id: targetId, direction },
  });
}

export function undoPartnerSwipe(token: string, clubId: string, targetId: string) {
  return apiRequest<{ target_id: string; undone: boolean }>(`/me/clubs/${id(clubId)}/partners/swipes/${id(targetId)}`, {
    method: "DELETE",
    token,
  });
}

export async function fetchPartnerMatches(token: string) {
  return (await apiRequest<{ matches?: PartnerMatch[] }>("/me/partners/matches", { token })).matches ?? [];
}

export function endPartnerMatch(token: string, matchId: string) {
  return apiRequest<{ id: string; status: PartnerMatch["status"] }>(`/me/partners/matches/${id(matchId)}`, { method: "DELETE", token });
}

export function fetchPartnerMessages(token: string, matchId: string, cursor?: string | null) {
  return apiRequest<PartnerMessagePage>(`/me/partners/matches/${id(matchId)}/messages${query({ cursor })}`, { token });
}

export async function sendPartnerMessage(token: string, matchId: string, body: string) {
  return (await apiRequest<{ message: PartnerMessage }>(`/me/partners/matches/${id(matchId)}/messages`, { method: "POST", token, body: { body } }))
    .message;
}

export function markPartnerMessagesRead(token: string, matchId: string) {
  return apiRequest<{ read: number }>(`/me/partners/matches/${id(matchId)}/messages/read`, { method: "POST", token });
}

export function fetchPartnerSessions(token: string, matchId: string) {
  return apiRequest<PartnerSessions>(`/me/partners/matches/${id(matchId)}/sessions`, { token });
}

export async function suggestPartnerPlan(token: string, matchId: string, classId: string, body?: string | null) {
  return (
    await apiRequest<{ message: PartnerMessage }>(`/me/partners/matches/${id(matchId)}/plans`, {
      method: "POST",
      token,
      body: { class_id: classId, body: body ?? null },
    })
  ).message;
}

export function fetchPartnerSettings(token: string) {
  return apiRequest<PartnerSettings>("/me/partners/settings", { token });
}

export function putPartnerSettings(token: string, visible: boolean) {
  return apiRequest<PartnerSettings>("/me/partners/settings", { method: "PUT", token, body: { visible } });
}

export async function fetchBlocks(token: string) {
  return (await apiRequest<{ blocks?: BlockedPerson[] }>("/me/blocks", { token })).blocks ?? [];
}

export function blockPerson(token: string, userId: string) {
  return apiRequest<{ user_id: string; blocked: boolean }>("/me/blocks", { method: "POST", token, body: { user_id: userId } });
}

export function unblockPerson(token: string, userId: string) {
  return apiRequest<{ user_id: string; blocked: boolean }>(`/me/blocks/${id(userId)}`, { method: "DELETE", token });
}
