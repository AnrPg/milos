import { describe, expect, it } from "vitest";

import { notificationTargetUrl } from "@/components/notifications/notification-links";

import { buddyNotificationText, buddyNotificationUrl, isBuddyNotification } from "./buddy-links";

const t = (key: string, values?: Record<string, string | number>) =>
  values ? `${key}(${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(",")})` : key;

describe("buddy notification links", () => {
  it("opens the buddy page, the request and the conversation", () => {
    expect(buddyNotificationUrl("buddy_invite", {})).toBe("/me/buddy");
    expect(buddyNotificationUrl("support_request", { request_id: "r 1" })).toBe("/me/buddy/support/r%201");
    expect(buddyNotificationUrl("support_no_reply_nudge", { request_id: "r1" })).toBe("/me/buddy/support/r1");
    expect(buddyNotificationUrl("support_reply", { request_id: "r1", link_id: "l1" })).toBe("/me/buddy/l1/chat");
    expect(buddyNotificationUrl("support_reply", { request_id: "r1" })).toBe("/me/buddy/support/r1");
    expect(buddyNotificationUrl("buddy_message", { link_id: "l1" })).toBe("/me/buddy/l1/chat");
    expect(buddyNotificationUrl("coach_wellness_summary", { client_user_id: "u1" })).toBe("/admin/users/u1?tab=wellbeing#wellness_summary");
    expect(buddyNotificationUrl("chat_message", {})).toBeNull();
  });

  it("wins over the API's own paths in the bell", () => {
    expect(
      notificationTargetUrl({ type: "buddy_message", payload: { link_id: "l1", url: "/me/buddies/l1/messages" } }, "member"),
    ).toBe("/me/buddy/l1/chat");
    expect(notificationTargetUrl({ type: "buddy_accepted", payload: { url: "/me/buddies" } }, "coach")).toBe("/me/buddy");
  });

  it("knows its eight types", () => {
    expect(isBuddyNotification("buddy_weekly_summary")).toBe(true);
    expect(isBuddyNotification("referral_reward")).toBe(false);
  });
});

describe("buddy notification text", () => {
  it("names the person and keeps a message's words", () => {
    expect(buddyNotificationText("support_request", { nickname: "Maria" }, "title", t)).toContain("name=Maria");
    expect(buddyNotificationText("support_request", { nickname: "Maria", message: "Hard evening." }, "body", t)).toMatch(/^«Hard evening\.» · /);
  });

  it("reads a reply as its quick words or the buddy's own", () => {
    expect(buddyNotificationText("support_reply", { kind: "walk" }, "body", t)).toBe("reply.walk");
    expect(buddyNotificationText("support_reply", { kind: "text", text: "On my way" }, "body", t)).toBe("On my way");
    expect(buddyNotificationText("support_reply", { kind: "unknown" }, "body", t)).toBe("reply.here");
  });

  it("passes counts only for the weekly summaries", () => {
    const body = buddyNotificationText("buddy_weekly_summary", { nickname: "Maria", hard_moments: 3, overcome: "2", support_requests: 1 }, "body", t);
    expect(body).toContain("moments=3");
    expect(body).toContain("overcome=2");
    expect(body).toContain("requests=1");
    const coach = buddyNotificationText("coach_wellness_summary", { client_nickname: "Maria", sleep_nights: 4 }, "title", t);
    expect(coach).toContain("name=Maria");
  });

  it("leaves other notices alone", () => {
    expect(buddyNotificationText("chat_message", {}, "title", t)).toBeNull();
  });
});
