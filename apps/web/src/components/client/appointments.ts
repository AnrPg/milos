import type { AppointmentBooking, OfferedSlot } from "@/api/appointments";
import { bookingSlot } from "@/api/appointments";
import { entryDay } from "@/components/client/vault";

export type SlotDay = { day: string; slots: OfferedSlot[] };

/** Offered slots grouped by local calendar day, earliest first. */
export function groupSlotsByDay(slots: OfferedSlot[], timeZone?: string): SlotDay[] {
  const ordered = [...slots].sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at));
  const days: SlotDay[] = [];
  for (const slot of ordered) {
    const day = entryDay(slot.starts_at, timeZone);
    const last = days[days.length - 1];
    if (last && last.day === day) last.slots.push(slot);
    else days.push({ day, slots: [slot] });
  }
  return days;
}

function startsAt(booking: AppointmentBooking): number {
  const value = bookingSlot(booking)?.starts_at;
  return value ? Date.parse(value) : Number.NaN;
}

/**
 * Booked appointments that have not started are upcoming (soonest first);
 * everything else — past, cancelled, attended or missed — is history (newest first).
 */
export function splitAppointments(
  bookings: AppointmentBooking[],
  now: Date,
): { upcoming: AppointmentBooking[]; past: AppointmentBooking[] } {
  const upcoming: AppointmentBooking[] = [];
  const past: AppointmentBooking[] = [];
  for (const booking of bookings) {
    const start = startsAt(booking);
    if (booking.status === "booked" && Number.isFinite(start) && start >= now.getTime()) {
      upcoming.push(booking);
    } else {
      past.push(booking);
    }
  }
  upcoming.sort((a, b) => startsAt(a) - startsAt(b));
  past.sort((a, b) => (startsAt(b) || 0) - (startsAt(a) || 0));
  return { upcoming, past };
}

/**
 * Whether cancelling now would be late (the session is used). Unknown when
 * the cutoff is not known to the client; the server decides either way.
 */
export function isLateCancellation(
  startsAtIso: string | null | undefined,
  cutoffHours: number | null,
  now: Date,
): boolean | null {
  if (!startsAtIso || cutoffHours == null) return null;
  const start = Date.parse(startsAtIso);
  if (!Number.isFinite(start)) return null;
  return start - now.getTime() < cutoffHours * 3_600_000;
}
