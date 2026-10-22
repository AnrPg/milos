import { ApiError } from "@/api/client";
import type { CommunityEvent, EventDraft, EventPlace } from "@/api/events";
import {
  dateKeyInZone,
  deviceTimeZone,
  formatInZone,
  isValidTimeZone,
  sameClock,
  timeKeyInZone,
  zoneLabel,
  zonedText,
  zonedToInstant,
} from "@/lib/zoned-time";

/**
 * Pure helpers for club events (ADR-153): what «Θα έρθω» shows, late
 * cancels, prices, the date block, splitting lists, the optimistic answer and
 * turning the create sheet into a request.
 */

/** Giving up a place within this long before the start is a late cancel. */
export const LATE_CANCEL_MS = 2 * 60 * 60 * 1000;

type RsvpView = Pick<
  CommunityEvent,
  "cancelled" | "can_rsvp" | "starts_at" | "ends_at" | "spots_left" | "my" | "price_cents"
>;

/**
 * What the answer button offers: `going` / `waitlisted` (tap to give up),
 * `join` / `join_waitlist` (tap to come), or a state that takes no answer.
 */
export type RsvpState = "cancelled" | "over" | "going" | "waitlisted" | "join" | "join_waitlist" | "closed";

export function rsvpState(event: RsvpView, now: Date = new Date()): RsvpState {
  if (event.cancelled) return "cancelled";
  if (new Date(event.starts_at).getTime() <= now.getTime()) return "over";
  if (event.my?.status === "going") return "going";
  if (event.my?.status === "waitlisted") return "waitlisted";
  if (!event.can_rsvp) return "closed";
  return event.spots_left === 0 ? "join_waitlist" : "join";
}

export function hasEnded(event: Pick<CommunityEvent, "ends_at">, now: Date = new Date()): boolean {
  return new Date(event.ends_at).getTime() <= now.getTime();
}

/** Giving up a held place now would be a late cancel (within 2 hours of the start). */
export function isLateCancel(event: Pick<CommunityEvent, "starts_at" | "my">, now: Date = new Date()): boolean {
  if (event.my?.status !== "going") return false;
  const left = new Date(event.starts_at).getTime() - now.getTime();
  return left > 0 && left <= LATE_CANCEL_MS;
}

/** «€15» or «€12,50» in the reader's locale; null when free. */
export function formatPrice(cents: number, currency: string, locale: string): string | null {
  if (!cents) return null;
  const whole = cents % 100 === 0;
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currency || "EUR",
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(cents / 100);
}

/**
 * The date block of a row: short weekday (upper case) over the day of the
 * month, on the event's own clock (ADR-179: `timeZone` is the event's zone).
 */
export function dateBlock(iso: string, locale: string, timeZone?: string | null) {
  const zone = isValidTimeZone(timeZone) ? timeZone : undefined;
  const date = new Date(iso);
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: zone })
    .format(date)
    .replace(/\.$/, "")
    .toLocaleUpperCase(locale);
  const day = new Intl.DateTimeFormat(locale, { day: "numeric", timeZone: zone }).format(date);
  return { weekday, day };
}

/**
 * «19:00» on the event's clock; «19:00 Athens» when the viewer's clock reads
 * it differently (ADR-179). Without a zone, the device's clock.
 */
export function formatTime(iso: string, locale: string, timeZone?: string | null) {
  return zonedText(iso, timeZone, locale, "time");
}

/** «Σάββατο 25 Οκτωβρίου · 10:00–12:00», on the event's clock. */
export function formatWhen(startsAt: string, endsAt: string, locale: string, timeZone?: string | null) {
  const day = formatInZone(startsAt, timeZone, locale, { weekday: "long", day: "numeric", month: "long" });
  const range = [formatInZone(startsAt, timeZone, locale, "time"), formatInZone(endsAt, timeZone, locale, "time")].join("–");
  const viewer = deviceTimeZone();
  const differs = isValidTimeZone(timeZone) && isValidTimeZone(viewer) && !sameClock(startsAt, timeZone, viewer);
  return [day, differs ? `${range} ${zoneLabel(timeZone)}` : range].join(" · ");
}

/** The place's name, else its address. */
export function placeName(place: EventPlace): string {
  return place.name || place.address || "";
}

/** A place's address line under its name (address, neighbourhood, city). */
export function placeAddress(place: EventPlace): string {
  return [place.address !== place.name ? place.address : null, place.neighbourhood, place.city].filter(Boolean).join(", ");
}

/** Splits events into upcoming (soonest first) and past (latest first). */
export function splitEvents<T extends Pick<CommunityEvent, "starts_at" | "ends_at">>(events: T[], now: Date = new Date()) {
  const time = (event: T) => new Date(event.starts_at).getTime();
  const upcoming = events.filter((event) => new Date(event.ends_at).getTime() > now.getTime()).sort((a, b) => time(a) - time(b));
  const past = events.filter((event) => new Date(event.ends_at).getTime() <= now.getTime()).sort((a, b) => time(b) - time(a));
  return { upcoming, past };
}

/**
 * The event as it will look once the answer lands, so the button and the
 * count change at once: a place when one is left (or no limit), the waitlist
 * when full; giving up frees the place.
 */
export function optimisticRsvp<T extends CommunityEvent>(event: T, going: boolean): T {
  const status = event.my?.status ?? null;
  if (going) {
    if (status === "going" || status === "waitlisted") return event;
    const full = event.spots_left === 0;
    return {
      ...event,
      my: { ...(event.my ?? { late_cancel: false, paid: false, source: "member" as const }), status: full ? "waitlisted" : "going" },
      going_count: full ? event.going_count : event.going_count + 1,
      waitlist_count: full ? event.waitlist_count + 1 : event.waitlist_count,
      spots_left: full || event.spots_left == null ? event.spots_left : Math.max(0, event.spots_left - 1),
    };
  }
  if (status !== "going" && status !== "waitlisted") return event;
  const my = event.my ? { ...event.my, status: "cancelled" as const } : null;
  if (status === "waitlisted") return { ...event, my, waitlist_count: Math.max(0, event.waitlist_count - 1) };
  // A freed place goes to the longest-waiting person, so the count stays.
  if (event.waitlist_count > 0) return { ...event, my, waitlist_count: event.waitlist_count - 1 };
  return {
    ...event,
    my,
    going_count: Math.max(0, event.going_count - 1),
    spots_left: event.spots_left == null ? event.spots_left : event.spots_left + 1,
  };
}

/** The create sheet's fields as the person typed them. */
export type EventForm = {
  title: string;
  description: string;
  date: string; // yyyy-mm-dd, local
  time: string; // HH:mm, local
  durationMinutes: number;
  place: { kind: "location"; locationId: string } | { kind: "address"; name: string; address: string };
  capacity: string;
  paid: boolean;
  price: string;
  openToAll: boolean;
  guestPass: boolean;
  guestsPerMember: number;
  goodForFriends: boolean;
  repeatWeekly: boolean;
  repeatUntil: string;
  coverMediaId: string | null;
  /**
   * ADR-179: the clock the date and time are read on: the gym's, or the
   * event's own when it happens elsewhere. Null: this device's clock.
   */
  timeZone: string | null;
};

export const DURATIONS = [30, 45, 60, 90, 120, 180, 240];

/** «15», «15,5» or «15.50» → 1550; null when it isn't a price. */
export function parsePriceCents(value: string): number | null {
  const normalized = value.trim().replace(/\s/g, "").replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  return Math.round(Number(normalized) * 100);
}

/** The date and time inputs, read on `timeZone` (the device's clock without one), as one instant. */
export function localInstant(date: string, time: string, timeZone: string | null = null): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return null;
  const instant = zonedToInstant(date, time, timeZone);
  return Number.isNaN(instant.getTime()) ? null : instant;
}

/** yyyy-mm-dd and HH:mm of an instant on `timeZone` (the device's clock without one), for the inputs. */
export function localInputs(iso: string, timeZone: string | null = null) {
  return { date: dateKeyInZone(iso, timeZone), time: timeKeyInZone(iso, timeZone) };
}

export type FormProblem = "title" | "when" | "past" | "place" | "capacity" | "price" | "repeat";

/** What stops the form from being sent, or null. */
export function formProblem(form: EventForm, now: Date = new Date(), { editing = false } = {}): FormProblem | null {
  if (!form.title.trim()) return "title";
  const start = localInstant(form.date, form.time, form.timeZone);
  if (!start) return "when";
  if (!editing && start.getTime() <= now.getTime()) return "past";
  if (form.place.kind === "location" ? !form.place.locationId : !form.place.name.trim() && !form.place.address.trim()) return "place";
  if (form.capacity.trim() && !/^[1-9]\d{0,4}$/.test(form.capacity.trim())) return "capacity";
  if (form.paid && !(parsePriceCents(form.price) ?? 0)) return "price";
  if (!editing && form.repeatWeekly && (!/^\d{4}-\d{2}-\d{2}$/.test(form.repeatUntil) || form.repeatUntil < form.date)) return "repeat";
  return null;
}

/**
 * The request body of a valid form. A member group's event is always free,
 * for its members and without guest passes (the API enforces it too).
 */
export function eventRequest(
  form: EventForm,
  { group = false, editing = false, gymTimeZone = null }: { group?: boolean; editing?: boolean; gymTimeZone?: string | null } = {},
) {
  const start = localInstant(form.date, form.time, form.timeZone)!;
  const end = new Date(start.getTime() + form.durationMinutes * 60_000);
  const capacity = form.capacity.trim() ? Number(form.capacity.trim()) : null;
  const place =
    form.place.kind === "location"
      ? { location_id: form.place.locationId, place_name: null, address: null }
      : { location_id: null, place_name: form.place.name.trim() || null, address: form.place.address.trim() || null };
  const body: Omit<EventDraft, "channel_id"> = {
    title: form.title.trim(),
    description: form.description.trim() || null,
    starts_at: start.toISOString(),
    ends_at: end.toISOString(),
    ...place,
    capacity,
    price_cents: group || !form.paid ? 0 : (parsePriceCents(form.price) ?? 0),
    currency: "EUR",
    open_to_non_members: group ? false : form.openToAll,
    guest_pass_allowed: group ? false : form.guestPass,
    guests_per_member: group || !form.guestPass ? 0 : form.guestsPerMember,
    // «Καλό για φίλους» (ADR-156) only where a friend can come.
    good_for_friends: !group && (form.openToAll || form.guestPass) && form.goodForFriends,
    cover_media_id: form.coverMediaId,
  };
  // ADR-179: an event's own zone only when it differs from its gym's; while
  // the gym's zone is unknown here, the stored one is left as it is.
  if (gymTimeZone) body.time_zone = form.timeZone && form.timeZone !== gymTimeZone ? form.timeZone : null;
  if (!editing && form.repeatWeekly) body.repeat_until = form.repeatUntil;
  return body;
}

/** The form filled from an event, for editing. */
export function formFromEvent(event: CommunityEvent): EventForm {
  const timeZone = event.time_zone ?? null;
  const { date, time } = localInputs(event.starts_at, timeZone);
  const minutes = Math.max(15, Math.round((new Date(event.ends_at).getTime() - new Date(event.starts_at).getTime()) / 60_000));
  return {
    title: event.title,
    description: event.description ?? "",
    date,
    time,
    durationMinutes: minutes,
    place: event.place.location_id
      ? { kind: "location", locationId: event.place.location_id }
      : { kind: "address", name: event.place.name ?? "", address: event.place.address ?? "" },
    capacity: event.capacity ? String(event.capacity) : "",
    paid: event.price_cents > 0,
    price: event.price_cents > 0 ? String(event.price_cents / 100) : "",
    openToAll: event.open_to_non_members,
    guestPass: event.guest_pass_allowed,
    guestsPerMember: Math.max(1, event.guests_per_member),
    goodForFriends: event.good_for_friends,
    repeatWeekly: false,
    repeatUntil: "",
    coverMediaId: event.cover_media_id ?? null,
    timeZone,
  };
}

/** API error codes of events with their own copy (`err_<code>` in «Events»). */
export const EVENT_ERROR_CODES = [
  "event_cancelled",
  "event_started",
  "event_not_over",
  "not_invited",
  "guests_not_allowed",
  "inviter_not_going",
  "guest_limit_reached",
  "invalid_invite",
  "invalid_repeat",
  "event_is_free",
  "already_paid",
  "not_going",
  "trial_offer_already_sent",
  "nobody_to_offer",
  "trials_disabled",
] as const;

export function eventErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  const code = error.payload.code;
  return (EVENT_ERROR_CODES as readonly string[]).includes(code) ? ["err", code].join("_") : null;
}
