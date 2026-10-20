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
    ).toBe("/box/schedule");
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
    ).toBe("/box/schedule?open_slot=slot-9");
  });

  it("falls back to the schedule for a waitlist promotion without a class id", () => {
    expect(
      notificationTargetUrl({ type: "booking_waitlist_promoted", payload: {} }, "member"),
    ).toBe("/box/schedule");
  });

  it("links an expiring package to billing", () => {
    expect(
      notificationTargetUrl(
        { type: "package_expiring", payload: { url: "/account/billing", package_name: "Gold" } },
        "member",
      ),
    ).toBe("/me/payments");
    expect(
      notificationTargetUrl({ type: "package_expiring", payload: { package_name: "Gold" } }, "member"),
    ).toBe("/me/payments");
  });

  it("sends staff coaching notifications to the coaching queues", () => {
    expect(
      notificationTargetUrl(
        { type: "form_review_submitted", payload: { url: "/admin/coaching/form-reviews", form_review_id: "r1" } },
        "admin",
      ),
    ).toBe("/admin/coaching?tab=form-reviews");
    expect(
      notificationTargetUrl(
        { type: "coaching_reply_overdue", payload: { url: "/account/activity/chats?thread=t1", thread_id: "t1" } },
        "coach",
      ),
    ).toBe("/admin/coaching?tab=replies");
  });

  it("sends member coaching notifications to the coaching page", () => {
    expect(
      notificationTargetUrl(
        { type: "form_review_completed", payload: { url: "/account/coaching", form_review_id: "r1" } },
        "member",
      ),
    ).toBe("/box/coach");
    expect(
      notificationTargetUrl({ type: "nutrition_plan_updated", payload: { title: "Cut" } }, "athlete"),
    ).toBe("/box/coach");
  });

  it("opens appointments on the side of the reader", () => {
    expect(
      notificationTargetUrl({ type: "appointment_booked", payload: { url: "/staff/appointments", slot_id: "s1" } }, "admin"),
    ).toBe("/admin/appointments");
    expect(
      notificationTargetUrl({ type: "appointment_cancelled", payload: { url: "/account/coaching", slot_id: "s1" } }, "owner"),
    ).toBe("/admin/appointments");
    expect(
      notificationTargetUrl({ type: "appointment_cancelled", payload: { url: "/account/coaching", slot_id: "s1" } }, "member"),
    ).toBe("/box/appointments");
    expect(notificationTargetUrl({ type: "appointment_booked", payload: {} }, null)).toBe("/box/appointments");
  });
});

describe("notificationTargetUrl after the member-app move", () => {
  it("maps legacy member links stored in payloads to their new home", () => {
    expect(
      notificationTargetUrl({ type: "workout_moved", payload: { url: "/my-workouts?open=a1" } }, "member"),
    ).toBe("/box/workouts?open=a1");
    expect(
      notificationTargetUrl({ type: "pr_shared", payload: { url: "/my-workouts/pantheon" } }, "athlete"),
    ).toBe("/journal/pantheon");
  });
  it("opens the event page for event notifications and the trial sheet for the trial offer (ADR-153)", () => {
    expect(
      notificationTargetUrl({ type: "community_event_waitlist_promoted", payload: { event_id: "event-1" } }, "member"),
    ).toBe("/events/event-1");
    expect(notificationTargetUrl({ type: "community_event_message", payload: { event_id: "event-1" } }, "admin")).toBe(
      "/events/event-1",
    );
    expect(
      notificationTargetUrl(
        {
          type: "community_event_trial_offer",
          payload: { event_id: "event-1", url: "/b/kypseli?trial=1&referral_event_id=event-1" },
        },
        "member",
      ),
    ).toBe("/b/kypseli?trial=1&referral_event_id=event-1");
  });

  it("opens «Φέρε φίλο» at the box for the inviter and the queue for staff (ADR-156)", () => {
    expect(
      notificationTargetUrl({ type: "referral_progress", payload: { url: "/me/referrals?tab=invites&box=kypseli" } }, "member"),
    ).toBe("/me/referrals?tab=invites&box=kypseli");
    expect(notificationTargetUrl({ type: "referral_reward", payload: {} }, "member")).toBe("/me/referrals?tab=invites");
    expect(notificationTargetUrl({ type: "referral_review", payload: {} }, "admin")).toBe("/admin/finance?tab=referrals");
  });
});
