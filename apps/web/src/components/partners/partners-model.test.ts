import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { PartnerCard, PartnerMatch, PartnersClubOverview } from "@/api/partners";

import {
  activeFilters,
  draftRequest,
  draftValid,
  partnerErrorCode,
  partnersStage,
  profileDraft,
  sortMatches,
  toggleIn,
  unreadTotal,
  withoutCard,
} from "./partners-model";

const options = {
  levels: ["beginner", "intermediate", "advanced"],
  times: ["early", "midday", "afternoon", "evening", "weekend"],
  goals: ["strength", "conditioning", "weight_loss", "skills", "competition", "consistency"],
  genders: ["woman", "man", "other"],
  gender_preferences: ["any", "women", "men"],
  max_goals: 3,
  about_max: 140,
  daily_swipes: 200,
} as PartnersClubOverview["options"];

const overview = (patch: Partial<PartnersClubOverview>): PartnersClubOverview => ({
  club_id: "c1",
  offered: true,
  unavailable_reason: null,
  member: true,
  profile: null,
  swipes_remaining: 200,
  distance: null,
  options,
  ...patch,
});

const profile = (patch: Partial<NonNullable<PartnersClubOverview["profile"]>> = {}) => ({
  id: "p1",
  club_id: "c1",
  active: true,
  suspended: false,
  level: "intermediate" as const,
  times: ["early" as const],
  goals: ["strength" as const],
  about: null,
  gender: null,
  gender_preference: "any" as const,
  disciplines: [] as string[],
  ...patch,
});

const match = (id: string, patch: Partial<PartnerMatch> = {}): PartnerMatch => ({
  id,
  club_id: "c1",
  club_name: "Box",
  person: { id: `u-${id}`, nickname: id, avatar_url: null },
  partner_profile_id: `p-${id}`,
  status: "active",
  end_reason: null,
  ended_by_me: false,
  read_only: false,
  plannable: true,
  unread: 0,
  matched_at: "2026-11-01T10:00:00Z",
  last_message_at: null,
  ...patch,
});

describe("partnersStage", () => {
  it("shows nothing where Partners isn't offered or to non-members", () => {
    expect(partnersStage(undefined)).toBe("hidden");
    expect(partnersStage(overview({ offered: false, unavailable_reason: "disabled" }))).toBe("hidden");
    expect(partnersStage(overview({ member: false }))).toBe("hidden");
  });

  it("walks from intro to deck, paused and suspended", () => {
    expect(partnersStage(overview({}))).toBe("intro");
    expect(partnersStage(overview({ profile: profile() }))).toBe("deck");
    expect(partnersStage(overview({ profile: profile({ active: false }) }))).toBe("paused");
    expect(partnersStage(overview({ profile: profile({ suspended: true }) }))).toBe("suspended");
  });
});

describe("the profile draft", () => {
  it("keeps the options' order and stops goals at the limit", () => {
    expect(toggleIn(["weekend"], "early", options.times)).toEqual(["early", "weekend"]);
    expect(toggleIn(["early", "weekend"], "early", options.times)).toEqual(["weekend"]);
    expect(toggleIn(["strength", "skills", "competition"], "consistency", options.goals, 3)).toEqual([
      "strength",
      "skills",
      "competition",
    ]);
  });

  it("needs a time and one to three goals; about is trimmed and empty becomes null", () => {
    const draft = profileDraft(null);
    expect(draftValid(draft, options)).toBe(false);
    const filled = { ...draft, times: ["early" as const], goals: ["strength" as const], about: "  Hyrox  " };
    expect(draftValid(filled, options)).toBe(true);
    expect(draftRequest(filled)).toMatchObject({ active: true, about: "Hyrox", gender: null, gender_preference: "any" });
    expect(draftRequest({ ...filled, about: "   " }, false)).toMatchObject({ active: false, about: null });
    expect(draftValid({ ...filled, about: "a".repeat(141) }, options)).toBe(false);
  });

  it("starts from the saved profile", () => {
    expect(profileDraft(profile({ level: "advanced", about: "Hi" }))).toMatchObject({ level: "advanced", about: "Hi", times: ["early"] });
  });
});

describe("the deck and matches", () => {
  it("drops a swiped card and counts filters", () => {
    const card = (id: string) => ({ person: { id } }) as PartnerCard;
    expect(withoutCard([card("a"), card("b")], "a").map((c) => c.person.id)).toEqual(["b"]);
    expect(activeFilters({})).toBe(0);
    expect(activeFilters({ time: "early", goal: "skills", level: null })).toBe(2);
  });

  it("lists active conversations first, latest first, and sums unread", () => {
    const rows = [
      match("old", { matched_at: "2026-10-01T10:00:00Z" }),
      match("ended", { status: "ended", last_message_at: "2026-11-10T10:00:00Z" }),
      match("recent", { last_message_at: "2026-11-05T10:00:00Z", unread: 2 }),
      match("new", { matched_at: "2026-11-03T10:00:00Z", unread: 1 }),
    ];
    expect(sortMatches(rows).map((m) => m.id)).toEqual(["recent", "new", "old", "ended"]);
    expect(unreadTotal(rows)).toBe(3);
  });
});

describe("partnerErrorCode", () => {
  it("knows its own codes only", () => {
    expect(partnerErrorCode(new ApiError(429, "x", { code: "partner_swipe_limit" } as never))).toBe("partner_swipe_limit");
    expect(partnerErrorCode(new ApiError(500, "x", { code: "boom" } as never))).toBeNull();
    expect(partnerErrorCode(new Error("x"))).toBeNull();
  });
});
