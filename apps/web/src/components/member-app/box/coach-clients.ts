import type { AppointmentSlot } from "@/api/staff";
import type { ScheduleSlot } from "@/api/schedule";
import { membershipRoles, type MembershipLike } from "@/lib/role-navigation";
import { dateKeyInZone } from "@/lib/zoned-time";

// Pure helpers of Box › «Πελάτες μου» (ADR-198, vision §7.10): who gets the
// section and what the coach's check-in desk holds today.

/** The section is for someone who coaches at this provider (a solo coach is owner and coach). */
export function coachesHere(membership: MembershipLike | null | undefined): boolean {
  return membershipRoles(membership).includes("coach");
}

export type DeskAttendance = "attended" | "no_show" | null;

export type DeskPerson = {
  /** The booking whose attendance this row records. */
  bookingId: string;
  userId: string;
  name: string | null;
  attendance: DeskAttendance;
};

export type DeskSession = {
  id: string;
  /** The class or appointment slot itself. */
  slotId: string;
  kind: "class" | "appointment";
  startsAt: string;
  durationMinutes: number;
  /** The class name; null for a personal session (the screen names it). */
  title: string | null;
  roster: DeskPerson[];
};

function attendanceOf(status: string | null | undefined): DeskAttendance {
  return status === "attended" || status === "no_show" ? status : null;
}

/**
 * Today's sessions the coach runs, in the gym's time zone, earliest first:
 * their classes (approved members; a guest seat has no attendance of its
 * own) and their personal sessions (booked, attended or no-show clients).
 * A session nobody holds a place in has nothing to check in, so it is left out.
 */
export function todaysDesk(
  classes: ScheduleSlot[],
  appointments: AppointmentSlot[],
  coachUserId: string | null | undefined,
  zone: string | null | undefined,
  now: Date = new Date(),
): DeskSession[] {
  if (!coachUserId) return [];
  const today = dateKeyInZone(now, zone);
  const isToday = (iso: string) => dateKeyInZone(iso, zone) === today;

  const classSessions: DeskSession[] = classes
    .filter((slot) => slot.coach_user_id === coachUserId && isToday(slot.scheduled_at))
    .map((slot) => ({
      id: `class:${slot.id}`,
      slotId: slot.id,
      kind: "class",
      startsAt: slot.scheduled_at,
      durationMinutes: slot.duration_minutes,
      title: slot.name,
      roster: (slot.bookings ?? [])
        .filter((booking) => booking.status === "approved" && !booking.guest_name)
        .map((booking) => ({
          bookingId: booking.id,
          userId: booking.user_id,
          name: booking.user_nickname ?? null,
          attendance: attendanceOf(booking.attendance_status),
        })),
    }));

  const appointmentSessions: DeskSession[] = appointments
    .filter((slot) => !slot.cancelled_at && slot.coach_id === coachUserId && isToday(slot.starts_at))
    .map((slot) => ({
      id: `appointment:${slot.id}`,
      slotId: slot.id,
      kind: "appointment",
      startsAt: slot.starts_at,
      durationMinutes: slot.duration_minutes,
      title: null,
      roster: (slot.bookings ?? [])
        .filter((booking) => booking.status !== "cancelled" && !booking.cancelled_at)
        .map((booking) => ({
          bookingId: booking.id,
          userId: booking.user_id,
          name: booking.nickname ?? null,
          attendance: attendanceOf(booking.status),
        })),
    }));

  return [...classSessions, ...appointmentSessions]
    .filter((session) => session.roster.length > 0)
    .sort((a, b) => a.startsAt.localeCompare(b.startsAt));
}

/** How many on the roster are marked as there. */
export function checkedInCount(session: DeskSession): number {
  return session.roster.filter((person) => person.attendance === "attended").length;
}
