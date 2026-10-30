import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Partners («Συναθλητές», ADR-280): one public deck for all of Palee. The
 * overview says whether I may take part (verification) and holds my profile;
 * the deck, swipes, matches with their conversation and suggestions, the
 * Ρυθμίσεις switch, reports and blocked people. Nothing here names a club.
 */
export type PartnersOverview = components["schemas"]["PartnersOverview"];
export type PartnersEligibility = components["schemas"]["PartnersEligibility"];
export type EligibilityStatus = PartnersEligibility["status"];
export type PartnerOptions = components["schemas"]["PartnerOptions"];
export type PartnerProfile = components["schemas"]["PartnerProfile"];
export type PartnerProfileRequest = components["schemas"]["PartnerProfileRequest"];
export type PartnerCard = components["schemas"]["PartnerCard"];
export type PartnerBadge = components["schemas"]["PartnerBadge"];
export type PartnerDeck = components["schemas"]["PartnerDeck"];
export type PartnerSwipeResponse = components["schemas"]["PartnerSwipeResponse"];
export type PartnerMatch = components["schemas"]["PartnerMatch"];
export type PartnerMessage = components["schemas"]["PartnerMessage"];
export type PartnerMessagePage = components["schemas"]["PartnerMessagePage"];
export type PartnerPlan = components["schemas"]["PartnerPlan"];
export type PartnerPlanRequest = components["schemas"]["PartnerPlanRequest"];
export type PartnerSuggestion = components["schemas"]["PartnerSuggestion"];
export type PartnerSuggestions = components["schemas"]["PartnerSuggestions"];
export type SuggestionFeedbackReason = components["schemas"]["PartnerSuggestionFeedbackRequest"]["reason"];
export type PartnerReportRequest = components["schemas"]["PartnerReportRequest"];
export type PartnerReportReason = PartnerReportRequest["reason"];
export type PartnerReportResponse = components["schemas"]["PartnerReportResponse"];
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
  /** 2, 5, 10 or 25 km between neighbourhoods; left out, the API uses its default. */
  within_km?: number | null;
};

export const SUGGESTION_FEEDBACK_REASONS: readonly SuggestionFeedbackReason[] = ["not_near", "bad_time", "wrong_level", "other"];

export const PARTNERS_KEY = ["my", "partners"] as const;
export const PARTNERS_OVERVIEW_KEY = [...PARTNERS_KEY, "overview"] as const;
export const PARTNER_MATCHES_KEY = [...PARTNERS_KEY, "matches"] as const;
export const PARTNER_SETTINGS_KEY = [...PARTNERS_KEY, "settings"] as const;
export const BLOCKS_KEY = ["my", "blocks"] as const;

export const partnerDeckKey = (filters: PartnerFilters = {}) =>
  [
    ...PARTNERS_KEY,
    "deck",
    filters.time ?? null,
    filters.level ?? null,
    filters.goal ?? null,
    filters.discipline ?? null,
    filters.within_km ?? null,
  ] as const;
export const partnerMessagesKey = (matchId: string) => [...PARTNER_MATCHES_KEY, matchId, "messages"] as const;
export const partnerSuggestionsKey = (matchId: string) => [...PARTNER_MATCHES_KEY, matchId, "suggestions"] as const;

const id = (value: string) => encodeURIComponent(value);

function query(params: Record<string, string | null | undefined>) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([name, value]) => {
    if (value) search.set(name, value);
  });
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function fetchPartnersOverview(token: string) {
  return apiRequest<PartnersOverview>("/me/partners", { token });
}

export async function putPartnerProfile(token: string, body: PartnerProfileRequest) {
  return (await apiRequest<{ profile: PartnerProfile }>("/me/partners/profile", { method: "PUT", token, body })).profile;
}

export function fetchPartnerDeck(token: string, filters: PartnerFilters = {}) {
  return apiRequest<PartnerDeck>(
    `/me/partners/deck${query({
      time: filters.time,
      level: filters.level,
      goal: filters.goal,
      discipline: filters.discipline,
      within_km: filters.within_km ? String(filters.within_km) : null,
    })}`,
    { token },
  );
}

export function swipePartner(token: string, targetId: string, direction: SwipeDirection) {
  return apiRequest<PartnerSwipeResponse>("/me/partners/swipes", {
    method: "POST",
    token,
    body: { target_id: targetId, direction },
  });
}

export function undoPartnerSwipe(token: string, targetId: string) {
  return apiRequest<{ target_id: string; undone: boolean }>(`/me/partners/swipes/${id(targetId)}`, { method: "DELETE", token });
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

/** «Κλείστε μαζί»: at most three ideas, best first; none hides the card. */
export async function fetchPartnerSuggestions(token: string, matchId: string) {
  return (await apiRequest<PartnerSuggestions>(`/me/partners/matches/${id(matchId)}/suggestions`, { token })).suggestions ?? [];
}

/** «Πρότεινε»: posts the class, event or trial in the conversation as a plan. */
export async function proposePartnerPlan(token: string, matchId: string, plan: PartnerPlanRequest) {
  return (await apiRequest<{ message: PartnerMessage }>(`/me/partners/matches/${id(matchId)}/plans`, { method: "POST", token, body: plan }))
    .message;
}

/** «Δεν ταιριάζει»: counted anonymously, never shown to the other person. */
export function sendSuggestionFeedback(token: string, matchId: string, key: string, reason: SuggestionFeedbackReason) {
  return apiRequest<{ key: string; reason: SuggestionFeedbackReason }>(`/me/partners/matches/${id(matchId)}/suggestions/feedback`, {
    method: "POST",
    token,
    body: { key, reason },
  });
}

/** A report to the Palee team; it also blocks the person (ADR-280). */
export function reportPartner(token: string, body: PartnerReportRequest) {
  return apiRequest<PartnerReportResponse>("/me/partners/reports", { method: "POST", token, body });
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
