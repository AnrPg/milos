import type { ScheduleBooking } from "@/api/schedule";

/**
 * Splits a class roster into booked members and the waitlist. The waitlist is
 * in the order spots are offered: higher package priority first, then earliest
 * to join (ADR-097).
 */
export function splitRoster(bookings: ScheduleBooking[]) {
  const booked = bookings.filter((booking) => booking.status !== "waitlisted");
  const waitlist = bookings
    .filter((booking) => booking.status === "waitlisted")
    .sort(
      (a, b) =>
        (b.waitlist_priority ?? 0) - (a.waitlist_priority ?? 0) ||
        Date.parse(a.inserted_at) - Date.parse(b.inserted_at),
    );
  return { booked, waitlist };
}
