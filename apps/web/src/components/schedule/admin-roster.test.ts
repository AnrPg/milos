import { describe, expect, it } from "vitest";

import type { ScheduleBooking } from "@/api/schedule";
import { splitRoster } from "@/components/schedule/admin-roster";

function booking(id: string, status: ScheduleBooking["status"], inserted_at: string, waitlist_priority: number | null = 0): ScheduleBooking {
  return { id, user_id: `user-${id}`, status, inserted_at, waitlist_priority };
}

describe("splitRoster", () => {
  it("orders the waitlist by priority, then by join time", () => {
    const { booked, waitlist } = splitRoster([
      booking("a", "approved", "2026-10-01T08:00:00Z"),
      booking("b", "waitlisted", "2026-10-01T09:00:00Z", 0),
      booking("c", "waitlisted", "2026-10-01T10:00:00Z", 1),
      booking("d", "pending", "2026-10-01T08:30:00Z"),
      booking("e", "waitlisted", "2026-10-01T08:45:00Z", null),
      booking("f", "waitlisted", "2026-10-01T09:30:00Z", 1),
    ]);

    expect(booked.map((entry) => entry.id)).toEqual(["a", "d"]);
    expect(waitlist.map((entry) => entry.id)).toEqual(["f", "c", "e", "b"]);
  });

  it("does not reorder the caller's array", () => {
    const bookings = [booking("x", "waitlisted", "2026-10-01T10:00:00Z"), booking("y", "waitlisted", "2026-10-01T09:00:00Z")];
    splitRoster(bookings);
    expect(bookings.map((entry) => entry.id)).toEqual(["x", "y"]);
  });
});
