import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { PartnerCard, PartnerDeck, PartnerMatch, PartnerProfile, PartnersOverview } from "@/api/partners";

import {
  activeFilters,
  badgeText,
  commonTime,
  draftErrors,
  draftRequest,
  nearbyCard,
  partnerErrorCode,
  partnerFilters,
  partnersStage,
  planHref,
  profileDraft,
  sharedParts,
  sortMatches,
  suggestionReasons,
  toggleIn,
  unreadTotal,
  widerDistance,
  withoutCard,
} from "./partners-model";

const options: PartnersOverview["options"] = {
  levels: ["beginner", "intermediate", "advanced"],
  times: ["early", "midday", "afternoon", "evening", "weekend"],
  goals: ["strength", "conditioning", "weight_loss", "skills", "competition", "consistency"],
  genders: ["woman", "man", "other"],
  gender_preferences: ["any", "women", "men"],
  max_goals: 3,
  about_max: 140,
  daily_swipes: 200,
  default_within_km: 10,
  disciplines: ["crossfit", "running"],
  distances_km: [2, 5, 10, 25],
  max_disciplines: 5,
  report_reasons: ["unsafe", "fake", "minor", "harassment", "other"],
};

const profile = (patch: Partial<PartnerProfile> = {}): PartnerProfile => ({
  id: "p1",
  active: true,
  paused: false,
  adult_confirmed_at: "2026-10-30T08:00:00Z",
  show_box: true,
  level: "intermediate",
  times: ["early"],
  goals: ["strength"],
  disciplines: [],
  about: null,
  gender: null,
  gender_preference: "any",
  ...patch,
});

const overview = (status: PartnersOverview["eligibility"]["status"], patch: Partial<PartnersOverview> = {}): PartnersOverview => ({
  eligibility: { status, method: status === "verified" ? "membership" : null, next_step: null },
  profile: null,
  swipes_remaining: 200,
  distance: "available",
  options,
  ...patch,
});

const card = (id: string, patch: Partial<PartnerCard> = {}): PartnerCard => ({
  profile_id: `profile-${id}`,
  person: { id, nickname: id, avatar_url: null },
  level: "intermediate",
  times: ["early"],
  goals: ["strength"],
  disciplines: [],
  about: null,
  badge: null,
  shared: { times: [], goals: [], disciplines: [], same_level: false },
  ...patch,
});

const deck = (cards: PartnerCard[], patch: Partial<PartnerDeck> = {}): PartnerDeck => ({ cards, swipes_remaining: 200, within_km: 10, ...patch });

const match = (id: string, patch: Partial<PartnerMatch> = {}): PartnerMatch => ({
  id,
  partner_id: `person-${id}`,
  person: { id: `person-${id}`, nickname: id, avatar_url: null },
  status: "active",
  end_reason: null,
  ended_by_me: false,
  read_only: false,
  unread: 0,
  matched_at: "2026-10-20T08:00:00Z",
  last_message_at: null,
  ...patch,
});

describe("partnersStage (ADR-280)", () => {
  it("follows the verification first", () => {
    expect(partnersStage(overview("needs_verification"))).toBe("verify");
    expect(partnersStage(overview("in_review"))).toBe("in_review");
    expect(partnersStage(overview("rejected"))).toBe("rejected");
    expect(partnersStage(overview("suspended", { profile: profile() }))).toBe("suspended");
  });

  it("then my profile: none, paused in Ρυθμίσεις or by me, or the deck", () => {
    expect(partnersStage(overview("verified"))).toBe("setup");
    expect(partnersStage(overview("verified", { profile: profile({ paused: true }) }))).toBe("paused");
    expect(partnersStage(overview("verified", { profile: profile({ active: false }) }))).toBe("paused");
    expect(partnersStage(overview("verified", { profile: profile() }))).toBe("deck");
  });
});

describe("nearbyCard (Γύρω μου, vision §4.2)", () => {
  it("offers one card to start while I can still get in", () => {
    expect(nearbyCard(overview("needs_verification"), undefined)).toEqual({ kind: "start" });
    expect(nearbyCard(overview("verified"), undefined)).toEqual({ kind: "start" });
  });

  it("is hidden while in review, after a rejection or suspension, while paused, and before anything is known", () => {
    expect(nearbyCard(undefined, undefined).kind).toBe("hidden");
    // An answer it can't read hides the card instead of breaking Γύρω μου.
    expect(nearbyCard({} as PartnersOverview, undefined).kind).toBe("hidden");
    expect(nearbyCard(overview("in_review"), undefined).kind).toBe("hidden");
    expect(nearbyCard(overview("rejected"), undefined).kind).toBe("hidden");
    expect(nearbyCard(overview("suspended"), undefined).kind).toBe("hidden");
    expect(nearbyCard(overview("verified", { profile: profile({ paused: true }) }), deck([card("a")])).kind).toBe("hidden");
  });

  it("is hidden with nobody new or no swipes left", () => {
    const live = overview("verified", { profile: profile() });
    expect(nearbyCard(live, deck([])).kind).toBe("hidden");
    expect(nearbyCard(live, deck([card("a")], { swipes_remaining: 0 })).kind).toBe("hidden");
    expect(nearbyCard(live, undefined).kind).toBe("hidden");
  });

  it("counts the people and names the time most share with me", () => {
    const live = overview("verified", { profile: profile() });
    const cards = [
      card("a", { shared: { times: ["early"], goals: [], disciplines: [], same_level: false } }),
      card("b", { shared: { times: ["early", "evening"], goals: [], disciplines: [], same_level: false } }),
      card("c"),
    ];
    expect(nearbyCard(live, deck(cards))).toEqual({ kind: "people", count: 3, more: false, time: "early", timeCount: 2 });
    expect(nearbyCard(live, deck(Array.from({ length: 20 }, (_, index) => card(`p${index}`))))).toMatchObject({ more: true, time: null });
  });

  it("commonTime prefers the first time on a tie", () => {
    const cards = [
      card("a", { shared: { times: ["evening"], goals: [], disciplines: [], same_level: false } }),
      card("b", { shared: { times: ["early"], goals: [], disciplines: [], same_level: false } }),
    ];
    expect(commonTime(cards)).toEqual({ time: "evening", count: 1 });
    expect(commonTime([])).toBeNull();
  });
});

describe("the profile form", () => {
  it("chooses nothing for me except «Δείξε το box μου» on and «Οποιονδήποτε»", () => {
    expect(profileDraft(null)).toEqual({
      level: null,
      times: [],
      goals: [],
      disciplines: [],
      about: "",
      show_box: true,
      gender: null,
      gender_preference: "any",
      adult: false,
    });
    expect(profileDraft(profile({ show_box: false })).show_box).toBe(false);
    expect(profileDraft(profile()).adult).toBe(true);
  });

  it("needs the 18+ box on the first save only, a level, a time and one to three goals", () => {
    const empty = profileDraft(null);
    expect(draftErrors(empty, options, true)).toEqual({ adult: true, level: true, times: true, goals: true });
    expect(draftErrors(empty, options, false)).toEqual({ level: true, times: true, goals: true });
    const ready = { ...empty, adult: true, level: "beginner" as const, times: ["early" as const], goals: ["strength" as const] };
    expect(draftErrors(ready, options, true)).toEqual({});
    expect(draftErrors({ ...ready, about: "x".repeat(141) }, options, true)).toEqual({ about: true });
  });

  it("sends adult_confirmed only on the first save, with show_box and a trimmed line", () => {
    const draft = { ...profileDraft(null), adult: true, level: "beginner" as const, times: ["early" as const], goals: ["skills" as const], about: "  Hyrox  " };
    expect(draftRequest(draft, { firstSave: true })).toMatchObject({ active: true, adult_confirmed: true, show_box: true, about: "Hyrox", level: "beginner" });
    expect(draftRequest(draft)).not.toHaveProperty("adult_confirmed");
    expect(draftRequest({ ...draft, about: " " }, { active: false })).toMatchObject({ active: false, about: null });
  });

  it("toggles in the options' order and stops at the limit", () => {
    const order = ["a", "b", "c", "d"] as const;
    expect(toggleIn(["c"], "a", order)).toEqual(["a", "c"]);
    expect(toggleIn(["a", "c"], "a", order)).toEqual(["c"]);
    expect(toggleIn(["a", "b", "c"], "d", order, 3)).toEqual(["a", "b", "c"]);
  });
});

describe("the deck's filters", () => {
  const empty = { time: [], level: [], goal: [], discipline: [], within: [] };

  it("drops values no longer offered and leaves the distance to the API by default", () => {
    expect(partnerFilters({ ...empty, time: ["dawn"], goal: ["strength"], within: ["7"] }, options)).toEqual({
      time: null,
      level: null,
      goal: "strength",
      discipline: null,
      within_km: null,
    });
    expect(partnerFilters({ ...empty, within: ["5"], discipline: ["running"] }, options)).toMatchObject({ within_km: 5, discipline: "running" });
  });

  it("counts the narrowing filters, not the distance", () => {
    expect(activeFilters({ time: "early", level: "beginner", within_km: 5 })).toBe(2);
  });

  it("steps the distance out until the widest", () => {
    expect(widerDistance(5, options)).toBe(10);
    expect(widerDistance(10, options)).toBe(25);
    expect(widerDistance(25, options)).toBeNull();
  });

  it("drops the swiped card and keeps the order", () => {
    expect(withoutCard([card("a"), card("b"), card("c")], "b").map((item) => item.person.id)).toEqual(["a", "c"]);
  });
});

describe("the card", () => {
  it("names the box only when it is known (ADR-280 badges)", () => {
    expect(badgeText({ kind: "box", box_name: "CrossFit Kypseli" })).toEqual({ key: "badge_box", box: "CrossFit Kypseli" });
    expect(badgeText({ kind: "box", box_name: null })).toEqual({ key: "badge_member" });
    expect(badgeText({ kind: "member", box_name: null })).toEqual({ key: "badge_member" });
    expect(badgeText({ kind: "verified", box_name: null })).toEqual({ key: "badge_verified" });
    expect(badgeText({ kind: "sponsors", box_name: null })).toEqual({ key: "badge_sponsors" });
    expect(badgeText(null)).toBeNull();
  });

  it("lists «Κοινά» as level, times, goals, disciplines", () => {
    const shared = card("a", { level: "advanced", shared: { same_level: true, times: ["early"], goals: ["skills"], disciplines: ["running"] } });
    expect(sharedParts(shared)).toEqual([
      { kind: "level", value: "advanced" },
      { kind: "time", value: "early" },
      { kind: "goal", value: "skills" },
      { kind: "discipline", value: "running" },
    ]);
    expect(sharedParts(card("b"))).toEqual([]);
  });
});

describe("suggestions and plans", () => {
  const suggestion = { reasons: [] as string[], distances_km: [2.1, 3] as (number | null)[], booked_by_me: false, booked_by_partner: false };

  it("says why in plain words, in the API's order", () => {
    expect(suggestionReasons({ ...suggestion, reasons: ["shared_time:early", "level_fit", "near_both"] })).toEqual([
      { key: "reason_shared_time", time: "early" },
      { key: "reason_level_fit" },
      { key: "reason_distances", mine: 2.1, theirs: 3 },
    ]);
    expect(suggestionReasons({ ...suggestion, reasons: ["both_booked"] })).toEqual([{ key: "reason_both_booked" }]);
  });

  it("tells who booked, and skips what it can't say", () => {
    expect(suggestionReasons({ ...suggestion, reasons: ["one_booked"], booked_by_partner: true })).toEqual([{ key: "reason_partner_booked" }]);
    expect(suggestionReasons({ ...suggestion, reasons: ["one_booked"], booked_by_me: true })).toEqual([{ key: "reason_you_booked" }]);
    expect(suggestionReasons({ ...suggestion, reasons: ["near_both", "mystery"], distances_km: [null, 3] })).toEqual([]);
  });

  it("opens a class on the schedule, an event, and a trial in Γύρω μου", () => {
    expect(planHref({ kind: "class", id: "c 1" })).toBe("/box/schedule?open_slot=c%201");
    expect(planHref({ kind: "event", id: "e1" })).toBe("/events/e1");
    expect(planHref({ kind: "trial", id: "t1" })).toBe("/around?kind=boxes");
  });
});

describe("matches", () => {
  it("puts active conversations first, newest activity first", () => {
    const rows = sortMatches([
      match("old", { matched_at: "2026-10-01T00:00:00Z" }),
      match("ended", { status: "ended", last_message_at: "2026-10-29T00:00:00Z" }),
      match("new", { last_message_at: "2026-10-28T00:00:00Z" }),
    ]);
    expect(rows.map((row) => row.id)).toEqual(["new", "old", "ended"]);
  });

  it("adds up unread messages", () => {
    expect(unreadTotal([match("a", { unread: 2 }), match("b", { unread: 3 })])).toBe(5);
  });
});

describe("partnerErrorCode", () => {
  it("knows Partners' own codes only", () => {
    expect(partnerErrorCode(new ApiError(403, "x", { code: "partner_verification_required" } as never))).toBe("partner_verification_required");
    expect(partnerErrorCode(new ApiError(422, "x", { code: "partner_adult_required" } as never))).toBe("partner_adult_required");
    expect(partnerErrorCode(new ApiError(422, "x", { code: "something_else" } as never))).toBeNull();
    expect(partnerErrorCode(new Error("x"))).toBeNull();
  });
});
