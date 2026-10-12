import { describe, expect, it } from "vitest";

import { notificationTargetUrl } from "./notification-links";

describe("notificationTargetUrl", () => {
  it("normalizes legacy assignment links to the canonical admin route and query", () => {
    expect(
      notificationTargetUrl(
        { type: "workout_moved", payload: { url: "/my-workouts?open=assignment-1&date=2026-07-21" } },
        "admin",
      ),
    ).toBe(
      "/admin/coaching-assignments?open_assignment=assignment-1&date=2026-07-21",
    );
  });

  it("preserves the requested date when opening Personal Coaching", () => {
    expect(
      notificationTargetUrl(
        {
          type: "workout_assignment_requested",
          payload: { url: "/admin/coaching-assignments?date=2026-07-21" },
        },
        "admin",
      ),
    ).toBe("/admin/coaching-assignments?date=2026-07-21");
  });

  it("normalizes schedule links to the canonical admin class schedule", () => {
    expect(
      notificationTargetUrl(
        { type: "booking_pending", payload: { url: "/schedule?open=slot-1" } },
        "admin",
      ),
    ).toBe("/admin/class-schedule?open_slot=slot-1");
  });

  it("leaves member destinations unchanged", () => {
    expect(
      notificationTargetUrl(
        { type: "booking_approved", payload: { url: "/schedule" } },
        "member",
      ),
    ).toBe("/schedule");
  });

  it("rejects protocol-relative notification URLs", () => {
    expect(
      notificationTargetUrl(
        { type: "booking_approved", payload: { url: "//evil.example/phish" } },
        "member",
      ),
    ).toBeNull();
  });

  it("rejects absolute cross-origin notification URLs", () => {
    expect(
      notificationTargetUrl(
        { type: "booking_approved", payload: { url: "https://evil.example/phish" } },
        "admin",
      ),
    ).toBeNull();
  });

  it("opens the promoted class from a waitlist promotion", () => {
    expect(
      notificationTargetUrl(
        {
          type: "booking_waitlist_promoted",
          payload: { url: "/schedule", scheduled_class_id: "slot-9", booking_id: "booking-1" },
        },
        "member",
      ),
    ).toBe("/schedule?open_slot=slot-9");
  });

  it("falls back to the schedule for a waitlist promotion without a class id", () => {
    expect(
      notificationTargetUrl({ type: "booking_waitlist_promoted", payload: {} }, "member"),
    ).toBe("/schedule");
  });

  it("links an expiring package to billing", () => {
    expect(
      notificationTargetUrl(
        { type: "package_expiring", payload: { url: "/account/billing", package_name: "Gold" } },
        "member",
      ),
    ).toBe("/account/billing");
    expect(
      notificationTargetUrl({ type: "package_expiring", payload: { package_name: "Gold" } }, "member"),
    ).toBe("/account/billing");
  });
});
