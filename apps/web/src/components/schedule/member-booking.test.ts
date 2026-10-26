import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import type { EffectiveEntitlement } from "@/api/my-finance";
import type { ScheduleBooking, ScheduleSlot } from "@/api/schedule";
import { allowanceLabel } from "@/i18n/presentation";
import {
  canBringGuest,
  classStateBadge,
  includesGuestPasses,
  includesOpenGym,
  isEventSlot,
  localizeMemberBookingError,
  memberSlotState,
  slotCreditCost,
  slotLocationName,
  waitlistPositionLabel,
} from "./member-booking";

const translate = vi.fn((key: string, params?: Record<string, unknown>) =>
  params ? `${key}:${JSON.stringify(params)}` : key,
);

const NOW = new Date("2026-10-12T08:00:00Z");
const FUTURE = "2026-10-13T08:00:00Z";
const PAST = "2026-10-11T08:00:00Z";

function slot(overrides: Partial<ScheduleSlot> = {}): ScheduleSlot {
  return {
    id: "slot-1",
    master_workout_id: "workout-1",
    name: "WOD",
    duration_minutes: 60,
    scheduled_at: FUTURE,
    class_type_id: "type-1",
    class_type: { id: "type-1", name: "WOD", slug: "wod", sort_order: 0, archived_at: null },
    capacity: 10,
    auto_approve: true,
    booking_timeout_minutes: 60,
    approved_booking_count: 3,
    spots_remaining: 7,
    workout: null,
    bookings: [],
    ...overrides,
  };
}

function booking(overrides: Partial<ScheduleBooking>): ScheduleBooking {
  return { id: "booking-1", user_id: "user-1", status: "approved", inserted_at: PAST, ...overrides };
}

function entitlement(
  capabilities: string[],
  allowances: EffectiveEntitlement["allowances"] = {},
): EffectiveEntitlement {
  return {
    status: "active",
    enforcement_mode: "enforce_all",
    plan: { entitlement_version: 1, channels: [], capabilities },
    allowances,
    usage_entries: [],
  };
}

describe("memberSlotState", () => {
  it("never treats a waitlist place as a booking", () => {
    expect(
      memberSlotState(slot({ spots_remaining: 0, current_user_booking: booking({ status: "waitlisted", waitlist_position: 2 }) }), NOW),
    ).toEqual({ kind: "waitlisted", position: 2 });
  });

  it("reports approved and pending bookings", () => {
    expect(memberSlotState(slot({ current_user_booking: booking({ status: "pending" }) }), NOW)).toEqual({
      kind: "booked",
      status: "pending",
    });
  });

  it("offers the waitlist on a full future class without a booking", () => {
    expect(memberSlotState(slot({ spots_remaining: 0 }), NOW)).toEqual({ kind: "waitlist_open" });
    expect(memberSlotState(slot(), NOW)).toEqual({ kind: "bookable" });
  });

  it("closes past classes and rejected bookings", () => {
    expect(memberSlotState(slot({ scheduled_at: PAST }), NOW)).toEqual({ kind: "past" });
    expect(memberSlotState(slot({ current_user_booking: booking({ status: "rejected" }) }), NOW)).toEqual({
      kind: "unavailable",
    });
  });
});

describe("paused and cancelled classes (ADR-200)", () => {
  it("shows a cancelled class as cancelled, with its reason, whatever the booking", () => {
    const cancelled = slot({ cancelled_at: PAST, cancel_reason: "Flood", current_user_booking: booking({}) });
    expect(memberSlotState(cancelled, NOW)).toEqual({ kind: "cancelled", reason: "Flood" });
    expect(classStateBadge(cancelled)).toBe("cancelled");
  });

  it("keeps a booking in a paused class, and closes it to others", () => {
    const paused = slot({ paused_at: PAST });
    expect(memberSlotState(paused, NOW)).toEqual({ kind: "paused" });
    expect(memberSlotState({ ...paused, current_user_booking: booking({}) }, NOW)).toEqual({
      kind: "booked",
      status: "approved",
    });
    expect(classStateBadge(paused)).toBe("paused");
    expect(classStateBadge(slot())).toBeNull();
  });

  it("offers no guest place in a paused or cancelled class", () => {
    expect(canBringGuest(slot({ paused_at: PAST }), true, NOW)).toBe(false);
    expect(canBringGuest(slot({ cancelled_at: PAST }), true, NOW)).toBe(false);
  });
});

describe("slot details", () => {
  it("labels the waitlist position, or the place without one", () => {
    expect(waitlistPositionLabel(2, translate)).toBe('mbWaitlistPosition:{"position":2}');
    expect(waitlistPositionLabel(null, translate)).toBe("mbOnWaitlist");
  });

  it("shows the credit cost only above one visit", () => {
    const base = slot().class_type;
    expect(slotCreditCost(slot({ class_type: { ...base, credit_cost: 1 } }))).toBeNull();
    expect(slotCreditCost(slot({ class_type: { ...base, credit_cost: 3 } }))).toBe(3);
    expect(slotCreditCost(slot())).toBeNull();
  });

  it("recognises events and resolves the location name", () => {
    expect(isEventSlot(slot({ class_type: { ...slot().class_type, kind: "event" } }))).toBe(true);
    expect(isEventSlot(slot())).toBe(false);
    const locations = [{ id: "loc-1", name: "Downtown", address: null, archived_at: null }];
    expect(slotLocationName(slot({ location_id: "loc-1" }), locations)).toBe("Downtown");
    expect(slotLocationName(slot({ location_id: "loc-2" }), locations)).toBeNull();
    expect(slotLocationName(slot(), locations)).toBeNull();
  });
});

describe("canBringGuest", () => {
  it("needs guest passes, a free spot, a future class and no guest yet", () => {
    expect(canBringGuest(slot(), true, NOW)).toBe(true);
    expect(canBringGuest(slot(), false, NOW)).toBe(false);
    expect(canBringGuest(slot({ spots_remaining: 0 }), true, NOW)).toBe(false);
    expect(canBringGuest(slot({ scheduled_at: PAST }), true, NOW)).toBe(false);
    expect(
      canBringGuest(slot({ current_user_guest: booking({ id: "guest-1", guest_name: "Anna" }) }), true, NOW),
    ).toBe(false);
  });
});

describe("package inclusions", () => {
  it("detects guest passes and open gym from capabilities or allowances", () => {
    const usage = {
      limit: 2,
      period: "calendar_month" as const,
      period_start: "2026-10-01",
      period_end: "2026-10-31",
      committed: 0,
      extensions: 0,
      remaining: 2,
    };
    expect(includesGuestPasses(entitlement(["bring_guests"]))).toBe(true);
    expect(includesGuestPasses(entitlement([], { guest_passes: usage }))).toBe(true);
    expect(includesOpenGym(entitlement(["open_gym"]))).toBe(true);
    expect(includesOpenGym(entitlement([], { open_gym_visits: usage }))).toBe(true);
    expect(includesOpenGym(entitlement(["book_classes"]))).toBe(false);
    expect(includesOpenGym(null)).toBe(false);
  });
});

describe("localizeMemberBookingError", () => {
  it("formats the booking-window opening date in the member's locale", () => {
    const error = new ApiError(422, "Booking for this class is not open yet", {
      code: "booking_window_closed",
      params: { opens_at: "2026-10-20T07:00:00Z" },
    });
    const message = localizeMemberBookingError(error, translate, "en", "book");
    expect(message.startsWith("mbErrBookingOpensOn:")).toBe(true);
    expect(message).toContain("Oct");
  });

  it("falls back to the generic window message without a usable date", () => {
    const error = new ApiError(422, "closed", { code: "booking_window_closed" });
    expect(localizeMemberBookingError(error, translate, "en")).toBe("mbErrBookingWindowClosed");
  });

  it("explains missing or used-up guest passes", () => {
    const notIncluded = new ApiError(403, "no", {
      code: "finance_allowance_not_included",
      params: { allowance: "guest_passes" },
    });
    const exhausted = new ApiError(409, "no", {
      code: "finance_allowance_exhausted",
      params: { allowance: "guest_passes", limit: 2, committed: 2 },
    });
    expect(localizeMemberBookingError(notIncluded, translate, "en", "guest")).toBe("mbErrGuestPassesNotIncluded");
    expect(localizeMemberBookingError(exhausted, translate, "en", "guest")).toBe("mbErrGuestPassesUsedUp");
  });

  it("explains an open gym that is not part of the package", () => {
    const error = new ApiError(403, "no", { code: "finance_channel_not_included", params: { channel: "facility" } });
    expect(localizeMemberBookingError(error, translate, "en", "check_in")).toBe("mbErrOpenGymNotIncluded");
  });

  it.each([
    ["finance_membership_frozen", "mbErrMembershipFrozen"],
    ["finance_time_window_not_included", "mbErrOutsidePackageHours"],
    ["finance_location_not_included", "mbErrLocationNotIncluded"],
    ["slot_full", "mbErrSlotFull"],
    ["guest_already_booked", "mbErrGuestAlreadyBooked"],
    ["invalid_guest_name", "mbErrInvalidGuestName"],
  ])("maps %s through the shared error mapping", (code, key) => {
    expect(localizeMemberBookingError(new ApiError(409, "x", { code }), translate, "en")).toBe(key);
  });
});

describe("allowanceLabel", () => {
  it("labels the ADR-097 allowances", () => {
    expect(allowanceLabel("event_visits", translate)).toBe("mbAllowanceEventVisits");
    expect(allowanceLabel("guest_passes", translate)).toBe("mbAllowanceGuestPasses");
    expect(allowanceLabel("open_gym_visits", translate)).toBe("mbAllowanceOpenGymVisits");
  });
});
