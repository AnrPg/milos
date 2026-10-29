import { describe, expect, it } from "vitest";

import type { DayWorkout } from "@/api/day-workouts";
import type { ScheduleSlot } from "@/api/schedule";
import { coveringDayWorkout, dayWorkoutScope, dayWorkoutsOn, inheritedFrom } from "@/components/schedule/day-workouts";

const rule = (id: string, attrs: Partial<DayWorkout> = {}): DayWorkout => ({
  id,
  local_date: "2026-11-03",
  class_type_id: null,
  location_id: null,
  master_workout_id: `w-${id}`,
  workout: { id: `w-${id}`, title: id },
  ...attrs,
});

const slot = (attrs: Partial<ScheduleSlot> = {}) =>
  ({
    id: "s1",
    scheduled_at: "2026-11-03T16:00:00Z",
    class_type_id: "crossfit",
    class_type: { id: "crossfit", name: "CrossFit", slug: "crossfit", sort_order: 1, archived_at: null, kind: "class" },
    location_id: null,
    ...attrs,
  }) as ScheduleSlot;

describe("day workouts", () => {
  it("lists a day's rules with the all-classes one first", () => {
    const rules = [rule("type", { class_type_id: "crossfit" }), rule("all"), rule("other", { local_date: "2026-11-04" })];
    expect(dayWorkoutsOn(rules, "2026-11-03").map((r) => r.id)).toEqual(["all", "type"]);
  });

  it("finds the most specific rule covering a class on the gym's day", () => {
    const rules = [rule("all"), rule("type", { class_type_id: "crossfit" }), rule("yoga", { class_type_id: "yoga" })];
    expect(coveringDayWorkout(rules, slot(), "Europe/Athens")?.id).toBe("type");
    // 23:30 UTC on the 2nd is already the 3rd in Athens.
    expect(coveringDayWorkout([rule("all")], slot({ scheduled_at: "2026-11-02T23:30:00Z" }), "Europe/Athens")?.id).toBe("all");
    expect(coveringDayWorkout([rule("all")], slot({ scheduled_at: "2026-11-02T20:00:00Z" }), "Europe/Athens")).toBeNull();
  });

  it("never covers an event with an all-classes rule", () => {
    const event = slot({ class_type: { id: "seminar", name: "Seminar", slug: "seminar", sort_order: 2, archived_at: null, kind: "event" }, class_type_id: "seminar" });
    expect(coveringDayWorkout([rule("all")], event, "Europe/Athens")).toBeNull();
    expect(coveringDayWorkout([rule("named", { class_type_id: "seminar" })], event, "Europe/Athens")?.id).toBe("named");
  });

  it("names a rule's scope and counts the classes that inherited it", () => {
    const names = { allClasses: "All classes", classType: (id: string) => ({ crossfit: "CrossFit" })[id], location: (id: string) => ({ north: "North" })[id] };
    expect(dayWorkoutScope(rule("all"), names)).toBe("All classes");
    expect(dayWorkoutScope(rule("t", { class_type_id: "crossfit", location_id: "north" }), names)).toBe("CrossFit · North");
    expect(inheritedFrom(rule("all"), [slot({ day_workout_id: "all" }), slot({ id: "s2", day_workout_id: null })])).toHaveLength(1);
  });
});
