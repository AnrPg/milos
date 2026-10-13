import { describe, expect, it } from "vitest";

import type { AppointmentBooking, OfferedSlot } from "@/api/appointments";
import { groupSlotsByDay, isLateCancellation, splitAppointments } from "@/components/client/appointments";

function slot(id: string, startsAt: string): OfferedSlot {
  return {
    id,
    starts_at: startsAt,
    capacity: 1,
    coach_id: "coach",
    duration_minutes: 60,
    format: "one_to_one",
    kind: "pt_session",
    spots_remaining: 1,
  };
}

function booking(id: string, status: AppointmentBooking["status"], startsAt: string): AppointmentBooking {
  return {
    id,
    status,
    allowance: "pt_sessions",
    slot_id: `slot-${id}`,
    user_id: "me",
    slot: { starts_at: startsAt },
  };
}

describe("appointment helpers", () => {
  it("groups slots by day in start order", () => {
    const days = groupSlotsByDay(
      [slot("c", "2026-10-14T09:00:00Z"), slot("a", "2026-10-13T07:00:00Z"), slot("b", "2026-10-13T16:00:00Z")],
      "UTC",
    );
    expect(days.map((day) => [day.day, day.slots.map((value) => value.id)])).toEqual([
      ["2026-10-13", ["a", "b"]],
      ["2026-10-14", ["c"]],
    ]);
  });

  it("splits upcoming booked appointments from history", () => {
    const now = new Date("2026-10-12T12:00:00Z");
    const { upcoming, past } = splitAppointments(
      [
        booking("later", "booked", "2026-10-20T09:00:00Z"),
        booking("soon", "booked", "2026-10-13T09:00:00Z"),
        booking("cancelled", "cancelled", "2026-10-15T09:00:00Z"),
        booking("done", "attended", "2026-10-01T09:00:00Z"),
      ],
      now,
    );
    expect(upcoming.map((value) => value.id)).toEqual(["soon", "later"]);
    expect(past.map((value) => value.id)).toEqual(["cancelled", "done"]);
  });

  it("flags cancellations inside the cutoff", () => {
    const now = new Date("2026-10-12T12:00:00Z");
    expect(isLateCancellation("2026-10-12T20:00:00Z", 12, now)).toBe(true);
    expect(isLateCancellation("2026-10-13T20:00:00Z", 12, now)).toBe(false);
    expect(isLateCancellation("2026-10-13T20:00:00Z", null, now)).toBeNull();
  });
});
