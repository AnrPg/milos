import { describe, expect, it } from "vitest";

import type { AssignedWorkoutRecord } from "@/api/assigned-workouts";
import type { ScheduleSlot } from "@/api/schedule";

import { buildTodayTraining, defaultTodayItem, logSourceFor } from "./today-training";

const now = new Date(2026, 9, 15, 9, 0);
const at = (hour: number, day = 15) => new Date(2026, 9, day, hour, 0).toISOString();
const workout = (id: string, title = id) => ({ id, title, type: "for_time", sections: [] });

function slot(id: string, scheduledAt: string, overrides: Partial<ScheduleSlot> = {}): ScheduleSlot {
  return {
    id,
    master_workout_id: `w-${id}`,
    name: `Class ${id}`,
    duration_minutes: 60,
    scheduled_at: scheduledAt,
    class_type_id: "ct",
    class_type: { id: "ct", name: "CrossFit" } as ScheduleSlot["class_type"],
    capacity: 12,
    auto_approve: true,
    booking_timeout_minutes: 30,
    approved_booking_count: 1,
    spots_remaining: 11,
    workout: workout(`w-${id}`, "Fran"),
    current_user_booking: { id: `b-${id}`, user_id: "me", status: "approved", inserted_at: at(8) },
    bookings: [],
    ...overrides,
  };
}

function assignment(id: string, scheduledFor: string, overrides: Partial<AssignedWorkoutRecord> = {}): AssignedWorkoutRecord {
  return {
    id,
    master_workout_id: `w-${id}`,
    scheduled_for: scheduledFor,
    workout: { ...workout(`w-${id}`, "Strength A"), sections: [] },
    ...overrides,
  };
}

describe("buildTodayTraining", () => {
  it("lists today's booked class WODs by time, then today's programmes", () => {
    const result = buildTodayTraining({
      now,
      scheduleSlots: [slot("late", at(18)), slot("early", at(7)), slot("tomorrow", at(7, 16))],
      assignments: [assignment("a1", "2026-10-15"), assignment("a2", "2026-10-16")],
      executions: [],
    });
    expect(result.items.map((item) => item.key)).toEqual(["class:early", "class:late", "programme:a1"]);
    expect(result.items[0].execution).toEqual({ source: "class_booking", referenceId: "b-early" });
    expect(result.items[2].execution).toEqual({ source: "assigned", referenceId: "a1" });
    expect(result.resumeExecutionId).toBeNull();
  });

  it("skips classes without an approved booking or a workout", () => {
    const result = buildTodayTraining({
      now,
      scheduleSlots: [
        slot("pending", at(10), { current_user_booking: { id: "b", user_id: "me", status: "pending", inserted_at: at(8) } }),
        slot("none", at(11), { current_user_booking: null }),
        slot("empty", at(12), { workout: null }),
      ],
      assignments: [],
      executions: [],
    });
    expect(result.items).toEqual([]);
  });

  it("uses the member's own class version instead of the class WOD and does not list it twice", () => {
    const version = {
      assignment_id: "v1",
      master_workout_id: "w-v1",
      scheduled_for: "2026-10-15",
      execution_status: "completed" as const,
      workout: { ...workout("w-v1", "Fran (scaled)"), sections: [] },
    };
    const result = buildTodayTraining({
      now,
      scheduleSlots: [slot("c", at(18), { my_version: version })],
      assignments: [assignment("v1", "2026-10-15", { assignment_kind: "class_variant", source_slot_id: "c" })],
      executions: [],
    });
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      kind: "class",
      workout: { title: "Fran (scaled)" },
      execution: { source: "assigned", referenceId: "v1" },
      injuryContext: { surface: "assignment_detail", id: "v1" },
      completed: true,
    });
  });

  it("drops rejected programmes and class versions of classes not booked today", () => {
    const result = buildTodayTraining({
      now,
      scheduleSlots: [],
      assignments: [
        assignment("r", "2026-10-15", { my_athlete_status: "rejected" }),
        assignment("v", "2026-10-15", { assignment_kind: "class_variant" }),
      ],
      executions: [],
    });
    expect(result.items).toEqual([]);
  });

  it("resumes an unfinished execution", () => {
    const result = buildTodayTraining({
      now,
      scheduleSlots: [],
      assignments: [],
      executions: [
        { id: "done", status: "completed" },
        { id: "open", status: "paused" },
      ],
    });
    expect(result.resumeExecutionId).toBe("open");
  });
});

describe("defaultTodayItem", () => {
  it("selects the first item not yet done", () => {
    const { items } = buildTodayTraining({
      now,
      scheduleSlots: [],
      assignments: [
        assignment("done", "2026-10-15", { execution_status: "completed" }),
        assignment("todo", "2026-10-15"),
      ],
      executions: [],
    });
    expect(defaultTodayItem(items)?.key).toBe("programme:todo");
    expect(defaultTodayItem([])).toBeNull();
  });
});

describe("logSourceFor", () => {
  const sources = {
    classes: [{ id: "started", title: "CrossFit 07:00", scoreable_sections: [{ id: "s1" }] }],
    assignments: [{ id: "a1", title: "Strength A", scoreable_sections: [] }],
  };

  it("logs a started class or a due programme on its own source", () => {
    const { items } = buildTodayTraining({
      now,
      scheduleSlots: [slot("started", at(7)), slot("later", at(18))],
      assignments: [assignment("a1", "2026-10-15")],
      executions: [],
    });
    expect(logSourceFor(items[0], sources)).toEqual({
      sourceType: "class",
      referenceId: "started",
      title: "CrossFit 07:00",
      scoreableSections: [{ id: "s1" }],
    });
    expect(logSourceFor(items[1], sources)).toBeNull();
    expect(logSourceFor(items[2], sources)?.sourceType).toBe("assigned_workout");
    expect(logSourceFor(items[2], undefined)).toBeNull();
  });
});

describe("bookingCheckIn", async () => {
  const { bookingCheckIn } = await import("./today-training");
  const base = new Date("2026-10-16T17:00:00Z");
  const classAt = (status: string, extra: Record<string, unknown> = {}) =>
    ({
      id: "c",
      scheduled_at: base.toISOString(),
      duration_minutes: 60,
      current_user_booking: { id: "b", status, inserted_at: base.toISOString(), ...extra },
    }) as unknown as Parameters<typeof bookingCheckIn>[0];
  const minutes = (n: number) => new Date(base.getTime() + n * 60_000);

  it("opens 30 minutes before the class and closes when it ends", () => {
    expect(bookingCheckIn(classAt("approved"), minutes(-31)).canCheckIn).toBe(false);
    expect(bookingCheckIn(classAt("approved"), minutes(-30)).canCheckIn).toBe(true);
    expect(bookingCheckIn(classAt("approved"), minutes(59))).toEqual({ checkedIn: false, canCheckIn: true, live: true });
    expect(bookingCheckIn(classAt("approved"), minutes(60)).canCheckIn).toBe(false);
  });

  it("needs an approved booking and stops once checked in or marked by staff", () => {
    expect(bookingCheckIn(classAt("pending"), minutes(0)).canCheckIn).toBe(false);
    expect(bookingCheckIn(classAt("approved", { attendance_status: "attended" }), minutes(0))).toEqual({
      checkedIn: true,
      canCheckIn: false,
      live: true,
    });
    expect(bookingCheckIn(classAt("approved", { attendance_status: "no_show" }), minutes(0)).canCheckIn).toBe(false);
  });
});
