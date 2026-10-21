import { ApiError } from "@/api/client";
import type {
  PartnerCard,
  PartnerFilters,
  PartnerGoal,
  PartnerMatch,
  PartnerOptions,
  PartnerProfile,
  PartnerProfileRequest,
  PartnersClubOverview,
} from "@/api/partners";

/**
 * Pure rules of the Partners screens (ADR-169): what the club section shows,
 * the profile form's draft, the deck after a swipe and the matches list.
 */

export type PartnersStage = "hidden" | "intro" | "suspended" | "paused" | "deck";

/** What the Μέλη › Partners section shows; nothing at all where Partners isn't offered. */
export function partnersStage(overview: PartnersClubOverview | undefined): PartnersStage {
  if (!overview || !overview.offered || !overview.member) return "hidden";
  const profile = overview.profile;
  if (!profile) return "intro";
  if (profile.suspended) return "suspended";
  return profile.active ? "deck" : "paused";
}

export type ProfileDraft = Required<Pick<PartnerProfileRequest, "level" | "times" | "goals" | "gender_preference">> & {
  about: string;
  gender: PartnerProfileRequest["gender"];
};

export function profileDraft(profile: PartnerProfile | null | undefined): ProfileDraft {
  return {
    level: profile?.level ?? "intermediate",
    times: profile?.times ?? [],
    goals: profile?.goals ?? [],
    about: profile?.about ?? "",
    gender: profile?.gender ?? null,
    gender_preference: profile?.gender_preference ?? "any",
  };
}

/** Toggles a value in a list, keeping the options' order; goals stop at the limit. */
export function toggleIn<T extends string>(list: readonly T[], value: T, order: readonly T[], max = Infinity): T[] {
  if (list.includes(value)) return list.filter((item) => item !== value);
  if (list.length >= max) return [...list];
  return order.filter((item) => item === value || list.includes(item));
}

export function draftValid(draft: ProfileDraft, options: Pick<PartnerOptions, "max_goals" | "about_max">) {
  return (
    draft.times.length > 0 &&
    draft.goals.length > 0 &&
    draft.goals.length <= options.max_goals &&
    draft.about.trim().length <= options.about_max
  );
}

export function draftRequest(draft: ProfileDraft, active = true): PartnerProfileRequest {
  return {
    active,
    level: draft.level,
    times: draft.times,
    goals: draft.goals,
    about: draft.about.trim() || null,
    gender: draft.gender ?? null,
    gender_preference: draft.gender_preference,
  };
}

/** The deck once a card was swiped: the card leaves, the rest keep their order. */
export function withoutCard(cards: readonly PartnerCard[], userId: string): PartnerCard[] {
  return cards.filter((card) => card.person.id !== userId);
}

export function activeFilters(filters: PartnerFilters): number {
  return [filters.time, filters.level, filters.goal].filter(Boolean).length;
}

/** What the two share, as message keys and values, for the card's "you both" line. */
export function sharedHighlights(card: PartnerCard): { times: PartnerCard["times"]; goals: PartnerGoal[]; sameLevel: boolean } {
  return { times: card.shared.times ?? [], goals: card.shared.goals ?? [], sameLevel: card.shared.same_level };
}

/** Active conversations first, then by the latest message or the match itself. */
export function sortMatches(matches: readonly PartnerMatch[]): PartnerMatch[] {
  const at = (match: PartnerMatch) => Date.parse(match.last_message_at ?? match.matched_at) || 0;
  return [...matches].sort((a, b) => {
    if (a.status !== b.status) return a.status === "active" ? -1 : 1;
    return at(b) - at(a);
  });
}

export function unreadTotal(matches: readonly PartnerMatch[]): number {
  return matches.reduce((sum, match) => sum + (match.unread ?? 0), 0);
}

/** API error codes of Partners that have their own words. */
export const PARTNER_ERROR_CODES = [
  "partners_disabled",
  "partners_not_offered",
  "not_club_member",
  "partner_profile_required",
  "partner_profile_suspended",
  "invalid_partner_times",
  "invalid_partner_goals",
  "partner_about_too_long",
  "invalid_swipe",
  "partner_swipe_limit",
  "partner_already_matched",
  "partner_match_ended",
  "partner_match_read_only",
  "partner_plans_unavailable",
  "message_body_required",
  "cannot_block_self",
] as const;

export type PartnerErrorCode = (typeof PARTNER_ERROR_CODES)[number];

export function partnerErrorCode(error: unknown): PartnerErrorCode | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return (PARTNER_ERROR_CODES as readonly string[]).includes(error.payload.code) ? (error.payload.code as PartnerErrorCode) : null;
}
