import { addDaysToKey, dateKeyInZone, dateTimeLocalInZone, dateTimeLocalToIso, startOfDayInZone } from "@/lib/zoned-time";
import { ApiError } from "@/api/client";
import { localizeError, type UiTranslator } from "@/i18n/presentation";

// Pure helpers shared by the ADR-098 staff and finance screens.

/** Phase C API error codes and the Ui message key that explains each one. */
export const STAFF_ERROR_KEYS: Record<string, string> = {
  form_review_closed: "stfErrFormReviewClosed",
  appointment_slot_cancelled: "stfErrSlotCancelled",
  appointment_slot_in_past: "stfErrSlotInPast",
  appointment_slot_full: "stfErrSlotFull",
  appointment_format_not_included: "stfErrFormatNotIncluded",
  appointment_coach_not_included: "stfErrCoachNotIncluded",
  appointment_not_active: "stfErrAppointmentNotActive",
  appointment_coach_not_staff: "stfErrCoachNotStaff",
  invalid_attendance_status: "stfErrInvalidAttendance",
  already_booked: "stfErrAlreadyBooked",
  beneficiary_is_payer: "stfErrBeneficiaryIsPayer",
  not_a_shared_membership: "stfErrNotShared",
  beneficiary_limit_reached: "stfErrBeneficiaryLimit",
  minor_beneficiaries_not_allowed: "stfErrMinorsNotAllowed",
  not_a_corporate_package: "stfErrNotCorporatePackage",
  already_enrolled: "stfErrAlreadyEnrolled",
  corporate_seats_full: "stfErrSeatsFull",
  corporate_invoice_closed: "stfErrInvoiceClosed",
  invalid_invoice_status: "stfErrInvalidInvoiceStatus",
  corporate_package_requires_enrollment: "stfErrCorporateRequiresEnrollment",
  corporate_seat_billed_to_company: "stfErrSeatBilledToCompany",
  corporate_invoice_has_payments: "stfErrInvoiceHasPayments",
  payment_exceeds_balance: "stfErrPaymentExceedsBalance",
  invalid_payment_amount: "stfErrInvalidPaymentAmount",
  corporate_billing_email_missing: "stfErrBillingEmailMissing",
  mail_delivery_unavailable: "stfErrMailUnavailable",
};

export function staffErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError)) return null;
  const code = error.payload.code;
  return code ? (STAFF_ERROR_KEYS[code] ?? null) : null;
}

/** A friendly message for a Phase C error, falling back to the shared API error copy. */
export function staffErrorMessage(error: unknown, translate: UiTranslator): string {
  const key = staffErrorKey(error);
  return key ? translate(key) : localizeError(error, translate);
}

/** Accepts only absolute https:// links (the API rejects anything else). */
export function isHttpsUrl(value: string): boolean {
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" && Boolean(url.hostname);
  } catch {
    return false;
  }
}

/** "a, b,  b ,c" -> ["a", "b", "c"], at most `max` tags. */
export function parseTags(value: string, max = 8): string[] {
  const seen = new Set<string>();
  const tags: string[] = [];
  for (const raw of value.split(",")) {
    const tag = raw.trim().slice(0, 40);
    const key = tag.toLowerCase();
    if (!tag || seen.has(key)) continue;
    seen.add(key);
    tags.push(tag);
    if (tags.length >= max) break;
  }
  return tags;
}

/** Empty -> null, otherwise a non-negative integer; NaN for invalid input. */
export function optionalInt(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (!/^\d+$/.test(trimmed)) return Number.NaN;
  return Number(trimmed);
}

export type VideoState = "draft" | "published" | "archived";

export function videoState(video: { published_at?: string | null; archived_at?: string | null }): VideoState {
  if (video.archived_at) return "archived";
  if (video.published_at) return "published";
  return "draft";
}

export type ReplyUrgency = "overdue" | "due_soon" | "on_time";

/** Overdue per the API flag; due soon when the reply is due within `soonMs`. */
export function replyUrgency(
  item: { overdue: boolean; due_at?: string | null },
  now: Date = new Date(),
  soonMs = 2 * 60 * 60 * 1000,
): ReplyUrgency {
  if (item.overdue) return "overdue";
  if (!item.due_at) return "on_time";
  const due = new Date(item.due_at).getTime();
  if (Number.isNaN(due)) return "on_time";
  return due - now.getTime() <= soonMs ? "due_soon" : "on_time";
}

/** Sorts overdue first, then by due time (missing due times last), then by sent time. */
export function sortReplyQueue<T extends { overdue: boolean; due_at?: string | null; sent_at: string }>(
  items: T[],
): T[] {
  const due = (item: T) => (item.due_at ? new Date(item.due_at).getTime() : Number.POSITIVE_INFINITY);
  return [...items].sort((a, b) => {
    if (a.overdue !== b.overdue) return a.overdue ? -1 : 1;
    const byDue = due(a) - due(b);
    if (byDue !== 0) return byDue;
    return new Date(a.sent_at).getTime() - new Date(b.sent_at).getTime();
  });
}

function pad(value: number) {
  return String(value).padStart(2, "0");
}

/** Local calendar date key (YYYY-MM-DD) of a date. */
export function localDateKey(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Monday 00:00 (local) of the week containing `date`. */
export function startOfWeek(date: Date): Date {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const offset = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - offset);
  return start;
}

export function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

/** The [from, to) range shown by the appointments page. */
export function appointmentRange(anchor: Date, view: "week" | "day", zone: string | null = null): { from: Date; to: Date } {
  // ADR-179: with the practice's zone, its own days (midnight on its clock).
  if (zone) {
    const day = dateKeyInZone(anchor, zone);
    const weekday = (new Date(`${day}T12:00:00Z`).getUTCDay() + 6) % 7;
    const first = view === "day" ? day : addDaysToKey(day, -weekday);
    return { from: startOfDayInZone(first, zone), to: startOfDayInZone(addDaysToKey(first, view === "day" ? 1 : 7), zone) };
  }
  if (view === "day") {
    const from = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
    return { from, to: addDays(from, 1) };
  }
  const from = startOfWeek(anchor);
  return { from, to: addDays(from, 7) };
}

/** Groups slots by local start day, keeping days and slots in time order. */
export function groupSlotsByDay<T extends { starts_at: string }>(slots: T[], zone: string | null = null): Array<{ day: string; slots: T[] }> {
  const groups = new Map<string, T[]>();
  [...slots]
    .sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime())
    .forEach((slot) => {
      const key = zone ? dateKeyInZone(slot.starts_at, zone) : localDateKey(new Date(slot.starts_at));
      groups.set(key, [...(groups.get(key) ?? []), slot]);
    });
  return [...groups.entries()].map(([day, daySlots]) => ({ day, slots: daySlots }));
}

/** Bookings that still hold a place (booked or already attended / missed). */
export function activeBookings<T extends { status: string }>(bookings: T[] | null | undefined): T[] {
  return (bookings ?? []).filter((booking) => booking.status !== "cancelled");
}

/** Value for an <input type="datetime-local"> from a Date (local time). */
export function toDateTimeLocal(date: Date, zone: string | null = null): string {
  if (zone) return dateTimeLocalInZone(date, zone);
  return `${localDateKey(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** ISO timestamp from an <input type="datetime-local"> value, or null when invalid. */
export function fromDateTimeLocal(value: string, zone: string | null = null): string | null {
  if (!value) return null;
  if (zone && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) return dateTimeLocalToIso(value, zone);
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/** Allowed capacities for a slot format (one-to-one is 1, semi-private 2–4). */
export function capacityOptions(format: "one_to_one" | "semi_private"): number[] {
  return format === "one_to_one" ? [1] : [2, 3, 4];
}

/** Members still to add on a shared membership: limit counts the payer. */
export function remainingBeneficiaryPlaces(limit: unknown, activeBeneficiaries: number): number | null {
  const total = typeof limit === "number" ? limit : Number(limit);
  if (!Number.isFinite(total) || total <= 0) return null;
  return Math.max(0, total - 1 - activeBeneficiaries);
}

/** The chat thread where staff answer a member (same route chat notifications open). */
export function chatThreadHref(threadId: string): string {
  return `/me/activity/chats?thread=${encodeURIComponent(threadId)}`;
}

/** Active packages of the corporate type, the only ones a corporate client can use. */
export function corporatePackages<T extends Record<string, unknown>>(packages: T[]): T[] {
  return packages.filter((pkg) => pkg.package_type === "corporate" && pkg.active !== false);
}

/** "3 / 10" seats, or just "3" when the package sets no seat limit. */
export function seatUsage(activeSeats: number, seats: number | null | undefined): string {
  return typeof seats === "number" ? `${activeSeats} / ${seats}` : String(activeSeats);
}

/** Shared-membership subscriptions that still run and can take beneficiaries. */
export function sharedSubscriptions<T extends Record<string, unknown>>(subscriptions: T[]): T[] {
  return subscriptions.filter(
    (subscription) => subscription.package_type === "shared" && subscription.status === "active",
  );
}

/** "12,50" or "12.50" euros -> 1250 cents; null when not a positive amount. */
export function parseEuroToCents(value: string): number | null {
  const normalized = value.trim().replace(/\s/g, "").replace(",", ".");
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const cents = Math.round(Number(normalized) * 100);
  return cents > 0 ? cents : null;
}

/** 1250 cents -> "12.50" for an amount input. */
export function centsToInput(cents: number): string {
  return (Math.max(0, cents) / 100).toFixed(2);
}

/** Payment terms in days: whole number 0–120, otherwise null. */
export function parsePaymentTerms(value: string): number | null {
  const parsed = optionalInt(value);
  return parsed !== null && Number.isFinite(parsed) && parsed <= 120 ? parsed : null;
}

/** Formats a date-only ISO value (YYYY-MM-DD) without shifting it across time zones. */
export function formatIsoDate(locale: string, iso: string | null | undefined): string {
  if (!iso) return "—";
  const parsed = new Date(`${iso.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return iso;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" }).format(parsed);
}
