import { describe, expect, it } from "vitest";

import { notificationTargetUrl } from "./notification-links";

describe("notificationTargetUrl", () => {
  it("opens a person's message in its conversation and a message request in Requests (ADR-193)", () => {
    for (const role of ["member", "admin", null]) {
      expect(
        notificationTargetUrl({ type: "person_message", payload: { conversation_id: "c-1", url: "/me/messages/c-1" } }, role),
      ).toBe("/messages/c-1");
      expect(
        notificationTargetUrl({ type: "message_request", payload: { conversation_id: "c-1", url: "/me/messages/c-1" } }, role),
      ).toBe("/messages?folder=requests");
    }
    expect(notificationTargetUrl({ type: "person_message", payload: {} }, "member")).toBe("/messages");
  });

  it("opens the desk's visitors on the visitor who scanned the door", () => {
    expect(
      notificationTargetUrl({ type: "check_in_visitor", payload: { scan_id: "scan-1", url: "/admin/check-in?visitor=scan-1" } }, "admin"),
    ).toBe("/admin/check-in?visitor=scan-1#visitors");
    expect(notificationTargetUrl({ type: "check_in_visitor", payload: {} }, "admin")).toBe("/admin/check-in#visitors");
  });

  it("opens the password reset request a handler was told about", () => {
    for (const role of ["admin", "coach", "member", null]) {
      expect(
        notificationTargetUrl(
          { type: "password_reset_requested", payload: { request_id: "req-1", url: "/password-resets?request=req-1" } },
          role,
        ),
      ).toBe("/password-resets?request=req-1");
    }
    expect(notificationTargetUrl({ type: "password_reset_requested", payload: {} }, "admin")).toBe("/password-resets");
  });

  it("opens Settings after the person's password was reset", () => {
    expect(notificationTargetUrl({ type: "password_reset_completed", payload: { url: "/me/settings" } }, "member")).toBe("/me/settings#security");
    expect(notificationTargetUrl({ type: "password_reset_completed", payload: {} }, "admin")).toBe("/me/settings#security");
  });

  it("opens the demo's console from the idle-demo reminder", () => {
    expect(notificationTargetUrl({ type: "business_demo_idle", payload: { url: "/admin" } }, "owner")).toBe("/admin");
    expect(notificationTargetUrl({ type: "business_demo_idle", payload: {} }, "owner")).toBe("/admin");
  });

  it("opens Γύρω μου with the saved filter of an around alert", () => {
    expect(
      notificationTargetUrl({ type: "around_new_matches", payload: { filter_id: "f-1", url: "/around?filter=f-1" } }, "member"),
    ).toBe("/around?filter=f-1");
    expect(notificationTargetUrl({ type: "around_new_matches", payload: {} }, "member")).toBe("/around");
  });

  it("opens Συνδεδεμένες συσκευές on a Garmin sync error", () => {
    expect(notificationTargetUrl({ type: "device_sync_error", payload: { url: "/me/devices" } }, "member")).toBe("/me/devices");
    expect(notificationTargetUrl({ type: "device_sync_error", payload: {} }, "member")).toBe("/me/devices");
  });

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

  it("opens the schedule for a cancelled class (ADR-200)", () => {
    expect(notificationTargetUrl({ type: "class_cancelled", payload: {} }, "member")).toBe("/box/schedule");
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
    ).toBe("/journal/progress");
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

  it("opens the organiser console on a co-host request or answer (ADR-185)", () => {
    expect(
      notificationTargetUrl(
        { type: "community_event_cohost_request", payload: { event_id: "event-1", url: "/events/hosting?org=org-2&tab=requests" } },
        "admin",
      ),
    ).toBe("/events/hosting?org=org-2&tab=requests");
    expect(
      notificationTargetUrl(
        { type: "community_event_cohost_answered", payload: { event_id: "event-1", url: "/events/hosting?org=org-1&event=event-1" } },
        "member",
      ),
    ).toBe("/events/hosting?org=org-1&event=event-1");
    // Any other link falls back to the event page.
    expect(
      notificationTargetUrl({ type: "community_event_cohost_answered", payload: { event_id: "event-1", url: "https://evil.example" } }, "member"),
    ).toBe("/events/event-1");
  });
});
