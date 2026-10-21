import { describe, expect, it } from "vitest";

import type { AppointmentBooking } from "@/api/appointments";
import type { OrganizationMembership } from "@/api/organizations";
import type { PlatformPlan, PlanUsage } from "@/api/platform-plans";
import {
  boxLayoutFor,
  boxTitle,
  defaultTeamName,
  nextAppointment,
  ownsCoachPractice,
  shownMonthlyPrice,
  usageShare,
  usageTone,
} from "@/lib/solo-coach";

const now = new Date("2026-11-17T10:00:00Z");

function booking(id: string, startsAt: string, extra: Partial<AppointmentBooking> = {}, slot: object = {}) {
  return {
    id,
    slot_id: `slot-${id}`,
    user_id: "me",
    status: "booked",
    allowance: "pt_sessions",
    slot: { starts_at: startsAt, duration_minutes: 60, ...slot },
    ...extra,
  } as AppointmentBooking;
}

const plan = (overrides: Partial<PlatformPlan> = {}) =>
  ({
    code: "solo_coach",
    audience: "coach",
    name: "Solo coach",
    description: null,
    limits: { staff_seats: 2 },
    monthly_price_cents: 1900,
    annual_price_cents: 19000,
    currency: "EUR",
    price_status: "placeholder",
    trial_days: 30,
    is_default: true,
    public: true,
    active: true,
    position: 10,
    ...overrides,
  }) as PlatformPlan;

describe("solo-coach helpers", () => {
  it("gives an independent coach the coach layout and title", () => {
    expect(boxLayoutFor("coach")).toBe("coach");
    expect(boxLayoutFor("gym")).toBe("gym");
    expect(boxLayoutFor(undefined)).toBe("gym");
    expect(boxTitle("Νίκος Π.", "coach", "Personal coach")).toBe("Νίκος Π. · Personal coach");
    expect(boxTitle("Κυψέλη", "gym", "Personal coach")).toBe("Κυψέλη");
  });

  it("finds the next booked session that has not ended", () => {
    const appointments = [
      booking("past", "2026-11-17T08:00:00Z"),
      booking("running", "2026-11-17T09:30:00Z"),
      booking("later", "2026-11-18T09:00:00Z"),
      booking("cancelled", "2026-11-17T11:00:00Z", { status: "cancelled" }),
      booking("slot-cancelled", "2026-11-17T10:30:00Z", {}, { cancelled_at: "2026-11-16T10:00:00Z" }),
    ];
    expect(nextAppointment(appointments, now)?.booking.id).toBe("running");
    expect(nextAppointment([], now)).toBeNull();
  });

  it("never shows a placeholder price", () => {
    expect(shownMonthlyPrice(plan(), "en")).toBeNull();
    expect(shownMonthlyPrice(plan({ price_status: "confirmed" }), "en")).toBe("€19");
    expect(shownMonthlyPrice(plan({ price_status: "confirmed", monthly_price_cents: null }), "en")).toBeNull();
  });

  it("tones usage: a full hard limit is full, a soft one only warns", () => {
    const row = (overrides: Partial<PlanUsage>) =>
      ({ key: "staff_seats", used: 2, limit: 2, hard: true, state: "reached", ...overrides }) as PlanUsage;
    expect(usageTone(row({}))).toBe("full");
    expect(usageTone(row({ hard: false, key: "active_clients", state: "over" }))).toBe("warn");
    expect(usageTone(row({ state: "near" }))).toBe("warn");
    expect(usageTone(row({ state: "ok", used: 1 }))).toBe("ok");
    expect(usageShare(row({ used: 1 }))).toBe(0.5);
    expect(usageShare(row({ limit: null }))).toBeNull();
  });

  it("knows whether the account already runs a practice", () => {
    const membership = (kind: "gym" | "coach", roles: string[]) =>
      ({ role: roles[0], roles, organization: { id: kind, name: kind, slug: kind, provider_kind: kind } }) as unknown as OrganizationMembership;
    expect(ownsCoachPractice([membership("gym", ["owner"]), membership("coach", ["member"])])).toBe(false);
    expect(ownsCoachPractice([membership("coach", ["owner", "coach"])])).toBe(true);
  });

  it("names the team after the coach's first name", () => {
    expect(defaultTeamName("Νίκος Παπαδόπουλος")).toBe("Team Νίκος");
    expect(defaultTeamName("  Maria  ")).toBe("Team Maria");
  });
});
