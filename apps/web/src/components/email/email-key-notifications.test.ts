import { describe, expect, it } from "vitest";
import { emailKeyNotificationText } from "./email-key-notifications";

const t = (key: string, values?: Record<string, string>) => (values ? `${key}:${JSON.stringify(values)}` : key);

describe("emailKeyNotificationText", () => {
  it("ignores other notifications", () => {
    expect(emailKeyNotificationText("password_reset_requested", {}, "title", t)).toBeNull();
  });

  it("names the days left and the date", () => {
    expect(emailKeyNotificationText("email_key_expiring", { days_left: 30, expires_on: "2027-10-26" }, "body", t)).toBe(
      'notifKeyExpiringBody:{"days":"30","date":"2027-10-26"}',
    );
    expect(emailKeyNotificationText("email_key_expiring", {}, "body", t)).toBe('notifKeyExpiringBody:{"days":"—","date":"—"}');
    expect(emailKeyNotificationText("email_key_expiring", {}, "title", t)).toBe("notifKeyExpiringTitle");
    expect(emailKeyNotificationText("email_key_expiring", { days_left: "14", expires_on: "2027-10-26" }, "body", t)).toBe(
      'notifKeyExpiringBody:{"days":"14","date":"2027-10-26"}',
    );
  });

  it("says when the key has expired", () => {
    expect(emailKeyNotificationText("email_key_expiring", { days_left: -1 }, "title", t)).toBe("notifKeyExpiredTitle");
    expect(emailKeyNotificationText("email_key_expiring", { days_left: -2, expires_on: "2027-10-26" }, "body", t)).toBe(
      'notifKeyExpiredBody:{"date":"2027-10-26"}',
    );
  });
});
