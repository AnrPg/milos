import { describe, expect, it } from "vitest";

import { billingTab, canStay, leaveState, sessionsLeft, totalsByCurrency, validityProgress } from "./billing-model";

const usage = (limit: number | "unlimited", remaining: number | "unlimited") => ({
  limit,
  remaining,
  period: "subscription_period",
  period_start: "2026-10-01",
  period_end: "2026-10-31",
  committed: 0,
  extensions: 0,
});

describe("billingTab", () => {
  it("reads a known tab and falls back to the package", () => {
    expect(billingTab("transactions")).toBe("transactions");
    expect(billingTab("offers")).toBe("offers");
    expect(billingTab("documents")).toBe("membership");
    expect(billingTab(null)).toBe("membership");
  });
});

describe("totalsByCurrency", () => {
  it("sums each currency, money back counting negative", () => {
    expect(
      totalsByCurrency([
        { amount_cents: 4000, currency: "EUR" },
        { amount_cents: -500, currency: "EUR" },
        { amount_cents: 1200, currency: "BGN" },
      ]),
    ).toEqual([
      { currency: "BGN", cents: 1200 },
      { currency: "EUR", cents: 3500 },
    ]);
    expect(totalsByCurrency([])).toEqual([]);
  });
});

describe("sessionsLeft", () => {
  it("prefers class visits and reports unlimited packages", () => {
    expect(sessionsLeft({ allowances: { bookings: usage(20, 3), class_visits: usage(12, 5) } })).toEqual({
      unlimited: false,
      remaining: 5,
      limit: 12,
    });
    expect(sessionsLeft({ allowances: { class_visits: usage("unlimited", "unlimited") } })).toEqual({ unlimited: true });
    expect(sessionsLeft({ allowances: {} })).toBeNull();
    expect(sessionsLeft(null)).toBeNull();
  });
});

describe("validityProgress", () => {
  it("is the share of the window that has passed", () => {
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-10-16T00:00:00Z"))).toBeCloseTo(0.5, 1);
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-12-01"))).toBe(1);
    expect(validityProgress(null, "2026-10-31", new Date())).toBeNull();
  });
});

describe("leaveState (ADR-220)", () => {
  const actions = (leave: boolean) => ({ self_service_leave: leave });

  it("shows the last day while leaving, telling apart who decided", () => {
    expect(leaveState({ actions: actions(false), membership: { leaving_on: "2026-11-30", left_by: "member" } })).toEqual({
      kind: "leaving",
      leavingOn: "2026-11-30",
      byStaff: false,
    });
    expect(leaveState({ actions: actions(false), membership: { leaving_on: "2026-11-30", left_by: "staff" } })).toMatchObject({ byStaff: true });
  });

  it("offers leaving with the day the member would keep", () => {
    expect(leaveState({ actions: actions(true), membership: { leaving_on: null, leave_preview_on: "2026-11-27" } })).toEqual({
      kind: "can_leave",
      previewOn: "2026-11-27",
    });
  });

  it("offers nothing without a membership", () => {
    expect(leaveState({ actions: actions(true), membership: null })).toEqual({ kind: "none" });
    expect(leaveState({ actions: actions(false), membership: { leaving_on: null } })).toEqual({ kind: "none" });
  });

  it("lets the member stay until the last day has passed", () => {
    const now = new Date(2026, 10, 30, 23, 0);
    expect(canStay("2026-11-30", now)).toBe(true);
    expect(canStay("2026-12-01", now)).toBe(true);
    expect(canStay("2026-11-29", now)).toBe(false);
  });
});
