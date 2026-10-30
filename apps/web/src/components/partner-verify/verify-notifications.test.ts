import { describe, expect, it } from "vitest";

import { dateAtNoon, verifyNotificationText, verifyNotificationUrl } from "./verify-notifications";

const t = (key: string, values?: Record<string, string>) => (values ? `${key} ${JSON.stringify(values)}` : key);

describe("verification notifications", () => {
  it("opens the vouch requests for a sponsor and the verification for a candidate", () => {
    expect(verifyNotificationUrl("partner_vouch_request", {})).toBe("/partners/vouch-requests");
    expect(verifyNotificationUrl("partner_sponsor_penalty", { until: "2026-12-29" })).toBe("/partners/vouch-requests");
    expect(verifyNotificationUrl("partner_vouched", {})).toBe("/partners/verify");
    expect(verifyNotificationUrl("partner_verification_decided", { outcome: "approved" })).toBe("/partners");
    expect(verifyNotificationUrl("partner_verification_decided", { outcome: "rejected" })).toBe("/partners/verify");
    expect(verifyNotificationUrl("partner_verification_decided", { outcome: "expired" })).toBe("/partners/verify");
    expect(verifyNotificationUrl("partner_match", {})).toBeNull();
  });

  it("names who asks or vouched, never anything else", () => {
    expect(verifyNotificationText("partner_vouch_request", { candidate_nickname: "Giorgos" }, "title", t)).toBe(
      'notif.vouchRequest_title {"name":"Giorgos"}',
    );
    expect(verifyNotificationText("partner_vouched", {}, "title", t)).toBe('notif.vouched_title {"name":"someone"}');
  });

  it("words each outcome, with the reason of a rejection", () => {
    expect(verifyNotificationText("partner_verification_decided", { outcome: "approved" }, "title", t)).toBe("notif.decided_approved_title");
    expect(verifyNotificationText("partner_verification_decided", { outcome: "expired" }, "body", t)).toBe("notif.decided_expired_body");
    expect(verifyNotificationText("partner_verification_decided", { outcome: "rejected", reason: "Blurry" }, "body", t)).toBe(
      'notif.decided_rejected_reason {"reason":"Blurry"}',
    );
    expect(verifyNotificationText("partner_verification_decided", { outcome: "rejected" }, "body", t)).toBe("notif.decided_rejected_body");
  });

  it("dates the end of a sponsor's pause", () => {
    expect(verifyNotificationText("partner_sponsor_penalty", { until: "2026-12-29" }, "body", t, () => "29 Dec")).toBe(
      'notif.penalty_body {"date":"29 Dec"}',
    );
    expect(verifyNotificationText("partner_sponsor_penalty", {}, "body", t)).toBe("notif.penalty_bodyNoDate");
    expect(verifyNotificationText("other_type", {}, "title", t)).toBeNull();
  });

  it("reads a calendar date at noon UTC", () => {
    expect(dateAtNoon("2026-12-29").toISOString()).toBe("2026-12-29T12:00:00.000Z");
  });
});
