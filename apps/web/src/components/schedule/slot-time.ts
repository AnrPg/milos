import { addDaysToKey, dateKeyInZone, wallClock, zonedToInstant } from "@/lib/zoned-time";

/** Classes start on the half hour by default. */
const STEP_MINUTES = 30;
/** A new class starts at least this far ahead, so the form can be filled in. */
const LEAD_MINUTES = 15;
/** The usual start of a class day on the gym's clock. */
export const DEFAULT_CLASS_TIME = "09:00";

function pad(value: number) {
  return String(value).padStart(2, "0");
}

/**
 * The first half hour on the gym's clock that is at least LEAD_MINUTES ahead
 * of `now` (ADR-214). Crosses into the next day when the day is over.
 */
export function nextOpenStart(now: Date, zone: string | null): Date {
  const earliest = new Date(now.getTime() + LEAD_MINUTES * 60_000);
  const clock = wallClock(earliest, zone);
  const minutes = Math.ceil((clock.hour * 60 + clock.minute + (clock.second > 0 ? 1 : 0)) / STEP_MINUTES) * STEP_MINUTES;
  const dateKey = dateKeyInZone(earliest, zone);
  const dayKey = minutes >= 24 * 60 ? addDaysToKey(dateKey, 1) : dateKey;
  const dayMinutes = minutes % (24 * 60);
  return zonedToInstant(dayKey, `${pad(Math.floor(dayMinutes / 60))}:${pad(dayMinutes % 60)}`, zone);
}

/**
 * Where a new class on `dateKey` starts (ADR-214): 09:00 on the gym's clock,
 * or, when that has passed, the next open half hour, so the form never
 * suggests a time the API refuses.
 */
export function defaultClassStart(dateKey: string, zone: string | null, now: Date = new Date()): Date {
  const preferred = zonedToInstant(dateKey, DEFAULT_CLASS_TIME, zone);
  if (preferred.getTime() > now.getTime() + LEAD_MINUTES * 60_000) return preferred;
  return nextOpenStart(now, zone);
}

/** A class may not start at or before this moment (mirrors the API rule). */
export function startsInPast(scheduledAt: string, now: Date = new Date()): boolean {
  const at = new Date(scheduledAt).getTime();
  return Number.isNaN(at) || at <= now.getTime();
}

/** The gym's today, for date pickers that must not offer past days. */
export function todayKey(zone: string | null, now: Date = new Date()): string {
  return dateKeyInZone(now, zone);
}

/** The earliest value a new class's date-and-time picker offers: today on the gym's clock. */
export function earliestPickable(zone: string | null, now: Date = new Date()): string {
  return `${todayKey(zone, now)}T00:00`;
}
