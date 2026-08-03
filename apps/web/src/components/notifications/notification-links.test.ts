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
});
