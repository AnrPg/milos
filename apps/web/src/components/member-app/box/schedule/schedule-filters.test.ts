import { describe, expect, it } from "vitest";

import {
  CLASS_AUDIENCES,
  CLASS_LEVELS,
  WORKOUT_FOCUSES,
  type ScheduleBooking,
  type ScheduleSlot,
} from "@/api/schedule";

import {
  DEFAULT_SCHEDULE_FILTERS,
  activeFilterCount,
  atLocation,
  matchesScheduleFilters,
  nextMatch,
  parseScheduleFilters,
  rememberForGym,
  rememberedForGym,
  type ScheduleFilters,
} from "./schedule-filters";

const NOW = new Date("2026-10-20T06:00:00Z");
const VOCAB = { levels: CLASS_LEVELS, audiences: CLASS_AUDIENCES, focus: WORKOUT_FOCUSES };

function slot(overrides: Partial<ScheduleSlot> = {}): ScheduleSlot {
  return {
    id: "slot-1",
    master_workout_id: "workout-1",
    name: "WOD",
    duration_minutes: 60,
    scheduled_at: "2026-10-20T15:00:00Z",
    class_type_id: "type-1",
    class_type: { id: "type-1", name: "WOD", slug: "wod", sort_order: 0, archived_at: null, kind: "class", level: "all_levels", audiences: [] },
    capacity: 10,
    auto_approve: true,
    booking_timeout_minutes: 60,
    approved_booking_count: 3,
    spots_remaining: 7,
    workout: null,
    bookings: [],
    covered_by_package: true,
    ...overrides,
  };
}

const booking = (status: ScheduleBooking["status"]): ScheduleBooking => ({
  id: "b",
  user_id: "me",
  status,
  inserted_at: "2026-10-19T08:00:00Z",
});

const filters = (overrides: Partial<ScheduleFilters>) => ({ ...DEFAULT_SCHEDULE_FILTERS, ...overrides });
const matches = (s: ScheduleSlot, f: Partial<ScheduleFilters>) => matchesScheduleFilters(s, filters(f), NOW);

describe("matchesScheduleFilters", () => {
  it("lets everything through by default", () => {
    expect(matches(slot(), {})).toBe(true);
    expect(activeFilterCount(DEFAULT_SCHEDULE_FILTERS)).toBe(0);
  });

  it("filters availability, including full classes still open to the waitlist", () => {
    const full = slot({ spots_remaining: 0 });
    expect(matches(full, { spots: "open" })).toBe(false);
    expect(matches(full, { spots: "full" })).toBe(true);
    expect(matches(full, { spots: "full_waitlist" })).toBe(true);
    expect(matches(slot({ spots_remaining: 0, current_user_booking: booking("waitlisted") }), { spots: "full_waitlist" })).toBe(false);
    expect(matches(slot({ spots_remaining: 0, scheduled_at: "2026-10-19T15:00:00Z" }), { spots: "full_waitlist" })).toBe(false);
  });

  it("keeps out-of-package classes unless «Στο πακέτο μου» is on", () => {
    const outside = slot({ covered_by_package: false });
    expect(matches(outside, {})).toBe(true);
    expect(matches(outside, { packageOnly: true })).toBe(false);
  });

  it("narrows to own bookings, optionally with the waitlist", () => {
    expect(matches(slot(), { booked: "mine" })).toBe(false);
    expect(matches(slot({ current_user_booking: booking("approved") }), { booked: "mine" })).toBe(true);
    expect(matches(slot({ current_user_booking: booking("waitlisted") }), { booked: "mine" })).toBe(false);
    expect(matches(slot({ current_user_booking: booking("waitlisted") }), { booked: "mine_or_waitlist" })).toBe(true);
  });

  it("matches level, audience, focus, coach, kind and duration", () => {
    const tagged = slot({
      class_type: { id: "type-1", name: "Ladies", slug: "ladies", sort_order: 0, archived_at: null, kind: "event", level: "beginner", audiences: ["women"] },
      coach_user_id: "coach-1",
      duration_minutes: 30,
      workout: { id: "w", title: "W", type: "wod", sections: [], focus: ["strength", "legs"] },
    });
    expect(matches(tagged, { levels: ["beginner"], audiences: ["women"], focus: ["legs"], coachIds: ["coach-1"], kind: "event", durations: ["short"] })).toBe(true);
    expect(matches(tagged, { levels: ["advanced"] })).toBe(false);
    expect(matches(tagged, { audiences: ["teens"] })).toBe(false);
    expect(matches(tagged, { focus: ["mobility"] })).toBe(false);
    expect(matches(slot(), { focus: ["legs"] })).toBe(false);
    expect(matches(tagged, { coachIds: ["coach-2"] })).toBe(false);
    expect(matches(tagged, { kind: "class" })).toBe(false);
    expect(matches(tagged, { durations: ["long"] })).toBe(false);
  });

  it("filters by local start time", () => {
    const start = new Date("2026-10-20T15:00:00Z");
    const minutes = start.getHours() * 60 + start.getMinutes();
    expect(matches(slot(), { time: { from: minutes, to: minutes + 60 } })).toBe(true);
    expect(matches(slot(), { time: { from: minutes + 30, to: minutes + 60 } })).toBe(false);
  });
});

describe("location, counting and the next match", () => {
  it("treats classes without a location as part of every location", () => {
    expect(atLocation(slot({ location_id: "a" }), "a")).toBe(true);
    expect(atLocation(slot({ location_id: "b" }), "a")).toBe(false);
    expect(atLocation(slot({ location_id: null }), "a")).toBe(true);
    expect(atLocation(slot({ location_id: "b" }), null)).toBe(true);
  });

  it("counts every active filter once", () => {
    expect(activeFilterCount(filters({ spots: "open", levels: ["beginner"], time: { from: 360, to: 600 } }))).toBe(3);
  });

  it("finds the earliest class after a moment", () => {
    const later = slot({ id: "later", scheduled_at: "2026-10-23T15:00:00Z" });
    const sooner = slot({ id: "sooner", scheduled_at: "2026-10-22T15:00:00Z" });
    expect(nextMatch([later, sooner, slot()], new Date("2026-10-21T00:00:00Z"))?.id).toBe("sooner");
    expect(nextMatch([slot()], new Date("2026-10-21T00:00:00Z"))).toBeNull();
  });
});

describe("remembering per gym", () => {
  it("parses stale params defensively", () => {
    const parsed = parseScheduleFilters({ spots: "bogus", levels: ["beginner", "expert"], time: { from: 600, to: 300 }, packageOnly: true }, VOCAB);
    expect(parsed.spots).toBe("all");
    expect(parsed.levels).toEqual(["beginner"]);
    expect(parsed.time).toBeNull();
    expect(parsed.packageOnly).toBe(true);
    expect(parseScheduleFilters(null, VOCAB)).toEqual(DEFAULT_SCHEDULE_FILTERS);
  });

  it("keeps one entry per gym and only the newest few", () => {
    let params: unknown = null;
    for (let index = 0; index < 7; index += 1) {
      params = rememberForGym(params, `gym-${index}`, { filters: DEFAULT_SCHEDULE_FILTERS, locationId: null }, `2026-10-2${index}T00:00:00Z`);
    }
    const gyms = Object.keys((params as { gyms: object }).gyms);
    expect(gyms).toHaveLength(5);
    expect(gyms).not.toContain("gym-0");
    expect(rememberedForGym(params, "gym-6")?.locationId).toBeNull();
    const unchosen = rememberForGym(null, "gym", { filters: DEFAULT_SCHEDULE_FILTERS });
    expect(rememberedForGym(JSON.parse(JSON.stringify(unchosen)), "gym")?.locationId).toBeUndefined();
  });
});
