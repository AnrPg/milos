import { ApiError } from "@/api/client";
import type { ListFilter } from "@/components/filters/list-filter";
import type {
  PartnerBadge,
  PartnerCard,
  PartnerDeck,
  PartnerFilters,
  PartnerMatch,
  PartnerOptions,
  PartnerPlan,
  PartnerProfile,
  PartnerProfileRequest,
  PartnerSuggestion,
  PartnerTime,
  PartnersOverview,
} from "@/api/partners";

/**
 * Pure rules of the Partners screens (ADR-280): what /partners shows for my
 * verification and profile, the Γύρω μου card, the profile form, the deck's
 * filters, the card's badge and «Κοινά», and the suggestions' reasons.
 */

/** The verification flow (another screen); every «get verified» link goes there. */
export const PARTNERS_VERIFY_HREF = "/partners/verify";
export const PARTNERS_HREF = "/partners";
/** Where «Η περιοχή μου» is set (Ρυθμίσεις › Η περιοχή μου). */
export const PARTNERS_AREA_HREF = "/me/settings#around-area";
/** The deck API answers at most this many cards at a time (DeckPolicy.page_size). */
export const DECK_PAGE_SIZE = 20;

export type PartnersStage = "verify" | "in_review" | "rejected" | "suspended" | "setup" | "paused" | "deck";

/** What /partners shows: the verification state first, then my profile. */
export function partnersStage(overview: PartnersOverview): PartnersStage {
  switch (overview.eligibility.status) {
    case "needs_verification":
      return "verify";
    case "in_review":
      return "in_review";
    case "rejected":
      return "rejected";
    case "suspended":
      return "suspended";
    case "verified":
      break;
  }
  const profile = overview.profile;
  if (!profile) return "setup";
  return profile.active && !profile.paused ? "deck" : "paused";
}

export type NearbyCard = { kind: "hidden" } | { kind: "start" } | { kind: "people"; count: number; more: boolean; time: PartnerTime | null; timeCount: number };

/**
 * The «Συναθλητές κοντά σου» card of Γύρω μου (vision §4.2: hidden when it
 * has nothing to offer). People to swipe once I'm in; one entry card while I
 * still can start (not verified yet, or verified without a profile). Hidden
 * while a review is open, after a rejection or suspension, while paused,
 * with nobody new or no swipes left today.
 */
export function nearbyCard(overview: PartnersOverview | undefined, deck: PartnerDeck | undefined): NearbyCard {
  if (!overview) return { kind: "hidden" };
  const stage = partnersStage(overview);
  if (stage === "verify" || stage === "setup") return { kind: "start" };
  if (stage !== "deck" || !deck || deck.swipes_remaining <= 0) return { kind: "hidden" };
  const count = deck.cards.length;
  if (count === 0) return { kind: "hidden" };
  const common = commonTime(deck.cards);
  return { kind: "people", count, more: count >= DECK_PAGE_SIZE, time: common?.time ?? null, timeCount: common?.count ?? 0 };
}

/** The time most people in the deck share with me («3 προπονούνται νωρίς το πρωί όπως εσύ»). */
export function commonTime(cards: readonly PartnerCard[]): { time: PartnerTime; count: number } | null {
  const counts = new Map<PartnerTime, number>();
  cards.forEach((card) => card.shared.times.forEach((time) => counts.set(time, (counts.get(time) ?? 0) + 1)));
  let best: { time: PartnerTime; count: number } | null = null;
  for (const [time, count] of counts) {
    if (!best || count > best.count) best = { time, count };
  }
  return best;
}

export type ProfileDraft = {
  level: PartnerProfile["level"] | null;
  times: PartnerProfile["times"];
  goals: PartnerProfile["goals"];
  disciplines: string[];
  about: string;
  show_box: boolean;
  gender: PartnerProfile["gender"];
  gender_preference: PartnerProfile["gender_preference"];
  adult: boolean;
};

/** The form from my profile; nothing is chosen for me except «Δείξε το box μου» (on, ADR-280) and «Οποιονδήποτε». */
export function profileDraft(profile: PartnerProfile | null | undefined): ProfileDraft {
  return {
    level: profile?.level ?? null,
    times: profile?.times ?? [],
    goals: profile?.goals ?? [],
    disciplines: profile?.disciplines ?? [],
    about: profile?.about ?? "",
    show_box: profile?.show_box ?? true,
    gender: profile?.gender ?? null,
    gender_preference: profile?.gender_preference ?? "any",
    adult: Boolean(profile),
  };
}

/** Toggles a value in a list, keeping the options' order; nothing is added past the limit. */
export function toggleIn<T extends string>(list: readonly T[], value: T, order: readonly T[], max = Infinity): T[] {
  if (list.includes(value)) return list.filter((item) => item !== value);
  if (list.length >= max) return [...list];
  return order.filter((item) => item === value || list.includes(item));
}

export type DraftField = "adult" | "level" | "times" | "goals" | "about";
export type DraftErrors = Partial<Record<DraftField, true>>;

/** What is missing, per field (shown under each field after «Αποθήκευση»). The 18+ box only counts on the first save. */
export function draftErrors(draft: ProfileDraft, options: Pick<PartnerOptions, "max_goals" | "about_max">, firstSave: boolean): DraftErrors {
  const errors: DraftErrors = {};
  if (firstSave && !draft.adult) errors.adult = true;
  if (!draft.level) errors.level = true;
  if (draft.times.length === 0) errors.times = true;
  if (draft.goals.length === 0 || draft.goals.length > options.max_goals) errors.goals = true;
  if (draft.about.trim().length > options.about_max) errors.about = true;
  return errors;
}

export function draftRequest(draft: ProfileDraft, { active = true, firstSave = false }: { active?: boolean; firstSave?: boolean } = {}): PartnerProfileRequest {
  return {
    active,
    ...(firstSave ? { adult_confirmed: draft.adult } : {}),
    ...(draft.level ? { level: draft.level } : {}),
    times: draft.times,
    goals: draft.goals,
    disciplines: draft.disciplines,
    about: draft.about.trim() || null,
    show_box: draft.show_box,
    gender: draft.gender ?? null,
    gender_preference: draft.gender_preference,
  };
}

/** The deck's filters (vision §7.3), remembered on the `partners` surface. */
export const PARTNER_DECK_SHAPE = { time: "one", level: "one", goal: "one", discipline: "one", within: "one" } as const;
export type PartnerDeckFilter = ListFilter<typeof PARTNER_DECK_SHAPE>;

/** What the deck API is asked for: a stored value no longer offered is dropped; no distance means the API's default. */
export function partnerFilters(filter: PartnerDeckFilter, options: PartnerOptions): PartnerFilters {
  const pick = <T extends string>(values: readonly T[], value: string | undefined) => values.find((item) => item === value) ?? null;
  const km = Number(filter.within[0]);
  return {
    time: pick(options.times, filter.time[0]),
    level: pick(options.levels, filter.level[0]),
    goal: pick(options.goals, filter.goal[0]),
    discipline: pick(options.disciplines, filter.discipline[0]),
    within_km: options.distances_km.includes(km) ? km : null,
  };
}

/** «Φίλτρα (n)»: the narrowing filters chosen (the distance always has a value, so it isn't counted). */
export function activeFilters(filters: PartnerFilters): number {
  return [filters.time, filters.level, filters.goal, filters.discipline].filter(Boolean).length;
}

/** The next distance step out, for «Δοκίμασε μεγαλύτερη απόσταση»; null at the widest. */
export function widerDistance(current: number, options: Pick<PartnerOptions, "distances_km">): number | null {
  return [...options.distances_km].sort((a, b) => a - b).find((km) => km > current) ?? null;
}

/** The deck once a card was swiped: the card leaves, the rest keep their order. */
export function withoutCard(cards: readonly PartnerCard[], userId: string): PartnerCard[] {
  return cards.filter((card) => card.person.id !== userId);
}

export type BadgeText = { key: "badge_box" | "badge_member" | "badge_verified" | "badge_sponsors"; box?: string };

/** «✓ Μέλος στο <box>», «✓ Μέλος box», «✓ Επαληθευμένος», «✓ Με εγγυητές» (ADR-280). */
export function badgeText(badge: PartnerBadge | null | undefined): BadgeText | null {
  if (!badge) return null;
  switch (badge.kind) {
    case "box":
      return badge.box_name ? { key: "badge_box", box: badge.box_name } : { key: "badge_member" };
    case "member":
      return { key: "badge_member" };
    case "verified":
      return { key: "badge_verified" };
    case "sponsors":
      return { key: "badge_sponsors" };
  }
}

export type SharedPart = { kind: "level" | "time" | "goal" | "discipline"; value: string };

/** «Κοινά: …» in a fixed order: level, times, goals, disciplines. */
export function sharedParts(card: PartnerCard): SharedPart[] {
  return [
    ...(card.shared.same_level ? [{ kind: "level" as const, value: card.level }] : []),
    ...card.shared.times.map((value) => ({ kind: "time" as const, value })),
    ...card.shared.goals.map((value) => ({ kind: "goal" as const, value })),
    ...(card.shared.disciplines ?? []).map((value) => ({ kind: "discipline" as const, value })),
  ];
}

export type ReasonPart =
  | { key: "reason_both_booked" }
  | { key: "reason_you_booked" }
  | { key: "reason_partner_booked" }
  | { key: "reason_shared_time"; time: string }
  | { key: "reason_level_fit" }
  | { key: "reason_distances"; mine: number; theirs: number };

/**
 * A suggestion's reasons in plain words (ADR-280 §4: «και οι δύο πρωί · 2 και
 * 3 km»), in the order the API gives them. Unknown reasons are skipped, and
 * so are distances that aren't known for both.
 */
export function suggestionReasons(suggestion: Pick<PartnerSuggestion, "reasons" | "distances_km" | "booked_by_me" | "booked_by_partner">): ReasonPart[] {
  const parts: ReasonPart[] = [];
  suggestion.reasons.forEach((reason) => {
    const [name, value] = reason.split(":");
    if (name === "both_booked") parts.push({ key: "reason_both_booked" });
    else if (name === "one_booked") {
      if (suggestion.booked_by_me) parts.push({ key: "reason_you_booked" });
      else if (suggestion.booked_by_partner) parts.push({ key: "reason_partner_booked" });
    } else if (name === "shared_time" && value) parts.push({ key: "reason_shared_time", time: value });
    else if (name === "level_fit") parts.push({ key: "reason_level_fit" });
    else if (name === "near_both") {
      const [mine, theirs] = suggestion.distances_km;
      if (typeof mine === "number" && typeof theirs === "number") parts.push({ key: "reason_distances", mine, theirs });
    }
  });
  return parts;
}

/** Where a plan opens: a class on the schedule, an event, or Γύρω μου's boxes with trials. */
export function planHref(plan: Pick<PartnerPlan, "kind" | "id">): string {
  switch (plan.kind) {
    case "class":
      return `/box/schedule?open_slot=${encodeURIComponent(plan.id)}`;
    case "event":
      return `/events/${encodeURIComponent(plan.id)}`;
    case "trial":
      // The plan names a class of a box I don't belong to, without the box's address.
      return "/around?kind=boxes";
  }
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
  "partner_verification_required",
  "partner_suspended",
  "partner_adult_required",
  "partner_profile_required",
  "invalid_partner_level",
  "invalid_partner_times",
  "invalid_partner_goals",
  "invalid_partner_disciplines",
  "partner_about_too_long",
  "invalid_swipe",
  "partner_swipe_limit",
  "partner_already_matched",
  "partner_match_ended",
  "partner_match_read_only",
  "invalid_partner_plan",
  "invalid_partner_report_reason",
  "partner_report_note_too_long",
  "cannot_report_self",
  "partner_suggestion_unavailable",
  "message_body_required",
  "cannot_block_self",
] as const;

export type PartnerErrorCode = (typeof PARTNER_ERROR_CODES)[number];

export function partnerErrorCode(error: unknown): PartnerErrorCode | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return (PARTNER_ERROR_CODES as readonly string[]).includes(error.payload.code) ? (error.payload.code as PartnerErrorCode) : null;
}
