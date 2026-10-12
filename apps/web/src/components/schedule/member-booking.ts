import { ApiError } from "@/api/client";
import type { EffectiveEntitlement } from "@/api/my-finance";
import type { ScheduleLocation, ScheduleSlot } from "@/api/schedule";
import { localizeError, type UiTranslator } from "@/i18n/presentation";

// Member-side booking helpers for ADR-097 (waitlists, guests, events,
// locations, credit costs and open-gym check-ins). Kept pure so the schedule
// components stay declarative and the rules are unit-tested.

export type MemberSlotState =
  | { kind: "booked"; status: "approved" | "pending" }
  | { kind: "waitlisted"; position: number | null }
  | { kind: "bookable" }
  | { kind: "waitlist_open" }
  | { kind: "past" }
  | { kind: "unavailable" };

/** What the member can do with a class, from their own booking and capacity. */
export function memberSlotState(slot: ScheduleSlot, now: Date = new Date()): MemberSlotState {
  const booking = slot.current_user_booking;

  // A waitlist place is never a booking, even after the class has started.
  if (booking?.status === "waitlisted") {
    return { kind: "waitlisted", position: booking.waitlist_position ?? null };
  }
  if (booking?.status === "approved" || booking?.status === "pending") {
    return { kind: "booked", status: booking.status };
  }
  if (new Date(slot.scheduled_at) <= now) return { kind: "past" };
  if (booking) return { kind: "unavailable" };
  return slot.spots_remaining > 0 ? { kind: "bookable" } : { kind: "waitlist_open" };
}

export function waitlistPositionLabel(position: number | null, translate: UiTranslator) {
  return position ? translate("mbWaitlistPosition", { position }) : translate("mbOnWaitlist");
}

/** Visits one booking uses, shown only when a class costs more than one. */
export function slotCreditCost(slot: ScheduleSlot): number | null {
  const cost = slot.class_type?.credit_cost;
  return typeof cost === "number" && cost > 1 ? cost : null;
}

export function isEventSlot(slot: ScheduleSlot) {
  return slot.class_type?.kind === "event";
}

export function slotLocationName(slot: ScheduleSlot, locations: ScheduleLocation[] | undefined) {
  if (!slot.location_id) return null;
  return locations?.find((location) => location.id === slot.location_id)?.name ?? null;
}

/** "Bring a guest" needs a free spot, a future class and no guest booked yet. */
export function canBringGuest(slot: ScheduleSlot, guestsIncluded: boolean, now: Date = new Date()) {
  if (!guestsIncluded || slot.current_user_guest) return false;
  if (new Date(slot.scheduled_at) <= now) return false;
  return slot.spots_remaining > 0;
}

function planIncludes(
  entitlement: EffectiveEntitlement | null | undefined,
  capability: string,
  allowance: string,
) {
  if (!entitlement?.plan) return false;
  return entitlement.plan.capabilities.includes(capability) || Boolean(entitlement.allowances[allowance]);
}

export function includesGuestPasses(entitlement: EffectiveEntitlement | null | undefined) {
  return planIncludes(entitlement, "bring_guests", "guest_passes");
}

export function includesOpenGym(entitlement: EffectiveEntitlement | null | undefined) {
  return planIncludes(entitlement, "open_gym", "open_gym_visits");
}

export type MemberBookingAction = "book" | "waitlist" | "guest" | "withdraw" | "check_in";

const NOT_INCLUDED_CODES = new Set([
  "finance_allowance_not_included",
  "finance_capability_not_included",
  "finance_channel_not_included",
]);

function formatOpensAt(value: unknown, locale: string) {
  if (typeof value !== "string") return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat(locale, {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

/**
 * Localizes booking, waitlist, guest and check-in failures. Adds the
 * context the generic `localizeError` mapping cannot know (the action and the
 * member's locale for dates) and falls back to it for everything else.
 */
export function localizeMemberBookingError(
  error: unknown,
  translate: UiTranslator,
  locale: string,
  action: MemberBookingAction = "book",
) {
  if (error instanceof ApiError) {
    const code = error.payload.code;
    const params = error.payload.params ?? {};

    if (code === "booking_window_closed") {
      const date = formatOpensAt(params.opens_at, locale);
      if (date) return translate("mbErrBookingOpensOn", { date });
    }
    if (action === "guest" && code && NOT_INCLUDED_CODES.has(code)) {
      return translate("mbErrGuestPassesNotIncluded");
    }
    if (action === "guest" && code === "finance_allowance_exhausted") {
      return translate("mbErrGuestPassesUsedUp");
    }
    if (action === "check_in" && code && NOT_INCLUDED_CODES.has(code)) {
      return translate("mbErrOpenGymNotIncluded");
    }
    if (action === "check_in" && code === "finance_allowance_exhausted") {
      return translate("mbErrOpenGymUsedUp");
    }
  }

  return localizeError(error, translate);
}
