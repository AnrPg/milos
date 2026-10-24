import { describe, expect, it } from "vitest";

import type { ScheduleBooking, ScheduleSlot } from "@/api/schedule";
import type { AppointmentSlot } from "@/api/staff";

import { checkedInCount, coachesHere, todaysDesk } from "./coach-clients";

const ZONE = "Europe/Athens";
// 09:00 in Athens on 15 Oct 2026 (UTC+3).
const now = new Date("2026-10-15T06:00:00Z");

function booking(id: string, overrides: Partial<ScheduleBooking> = {}): ScheduleBooking {
  return { id, user_id: `u-${id}`, user_nickname: `Member ${id}`, status: "approved", inserted_at: "2026-10-01T00:00:00Z", ...overrides };
}

function slot(id: string, scheduledAt: string, overrides: Partial<ScheduleSlot> = {}): ScheduleSlot {
  return {
    id,
    name: `Class ${id}`,
    scheduled_at: scheduledAt,
    duration_minutes: 60,
    coach_user_id: "coach",
    bookings: [booking(`${id}-a`)],
    ...overrides,
  } as ScheduleSlot;
}

function appointment(id: string, startsAt: string, overrides: Partial<AppointmentSlot> = {}): AppointmentSlot {
  return {
    id,
    starts_at: startsAt,
    duration_minutes: 45,
    coach_id: "coach",
    capacity: 1,
    format: "one_to_one",
    kind: "pt_session",
    bookings: [{ id: `${id}-b`, slot_id: id, user_id: "client", nickname: "Eleni", status: "booked", allowance: "pt_sessions" }],
    ...overrides,
  } as AppointmentSlot;
}

describe("coachesHere", () => {
  it("is true for anyone holding the coach role, a solo coach (owner and coach) included", () => {
    expect(coachesHere({ role: "coach" })).toBe(true);
    expect(coachesHere({ role: "owner", roles: ["owner", "coach"] })).toBe(true);
    expect(coachesHere({ role: "member", roles: ["member"] })).toBe(false);
    expect(coachesHere({ role: "owner", roles: ["owner"] })).toBe(false);
    expect(coachesHere(null)).toBe(false);
  });
});

describe("todaysDesk", () => {
  it("keeps the coach's classes and sessions of the gym's day, earliest first", () => {
    const desk = todaysDesk(
      [
        slot("late", "2026-10-15T15:00:00Z"),
        slot("other-coach", "2026-10-15T08:00:00Z", { coach_user_id: "someone" }),
        // 23:30 UTC on the 14th is 02:30 on the 15th in Athens: today.
        slot("early", "2026-10-14T23:30:00Z"),
        // 22:00 UTC on the 15th is the 16th in Athens: tomorrow.
        slot("tomorrow", "2026-10-15T22:00:00Z"),
      ],
      [appointment("pt", "2026-10-15T09:00:00Z"), appointment("gone", "2026-10-15T10:00:00Z", { cancelled_at: "2026-10-14T10:00:00Z" })],
      "coach",
      ZONE,
      now,
    );
    expect(desk.map((session) => session.id)).toEqual(["class:early", "appointment:pt", "class:late"]);
    expect(desk[1]).toMatchObject({ kind: "appointment", slotId: "pt", title: null });
  });

  it("lists approved members with their attendance, never guests or other statuses", () => {
    const [session] = todaysDesk(
      [
        slot("c", "2026-10-15T10:00:00Z", {
          bookings: [
            booking("in", { attendance_status: "attended" }),
            booking("out", { attendance_status: "no_show" }),
            booking("open"),
            booking("guest", { guest_name: "Friend" }),
            booking("waiting", { status: "waitlisted" }),
          ],
        }),
      ],
      [],
      "coach",
      ZONE,
      now,
    );
    expect(session.roster.map((person) => [person.bookingId, person.attendance])).toEqual([
      ["in", "attended"],
      ["out", "no_show"],
      ["open", null],
    ]);
    expect(checkedInCount(session)).toBe(1);
  });

  it("reads a session's attendance from its booking status and drops cancelled bookings", () => {
    const [session] = todaysDesk(
      [],
      [
        appointment("semi", "2026-10-15T09:00:00Z", {
          bookings: [
            { id: "b1", slot_id: "semi", user_id: "u1", nickname: "A", status: "attended", allowance: "pt_sessions" },
            { id: "b2", slot_id: "semi", user_id: "u2", nickname: "B", status: "cancelled", allowance: "pt_sessions" },
            { id: "b3", slot_id: "semi", user_id: "u3", nickname: "C", status: "booked", allowance: "pt_sessions" },
          ],
        }),
      ],
      "coach",
      ZONE,
      now,
    );
    expect(session.roster.map((person) => [person.bookingId, person.attendance])).toEqual([
      ["b1", "attended"],
      ["b3", null],
    ]);
  });

  it("hides a session nobody holds a place in, and everything without a signed-in coach", () => {
    expect(todaysDesk([slot("empty", "2026-10-15T10:00:00Z", { bookings: [] })], [], "coach", ZONE, now)).toEqual([]);
    expect(todaysDesk([slot("c", "2026-10-15T10:00:00Z")], [], null, ZONE, now)).toEqual([]);
  });
});
