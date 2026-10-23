import { describe, expect, it } from "vitest";

import { passwordResetNotificationText } from "./reset-notifications";

const t = (key: string, values?: Record<string, string>) => (values ? `${key}:${JSON.stringify(values)}` : key);

describe("passwordResetNotificationText", () => {
  it("names the person who asked for a reset", () => {
    const payload = { request_id: "r-1", person_handle: "maria.k", person_name: "Μαρία 🏋️" };
    expect(passwordResetNotificationText("password_reset_requested", payload, "title", t)).toBe("notifRequestedTitle");
    expect(passwordResetNotificationText("password_reset_requested", payload, "body", t)).toBe(
      'notifRequestedBody:{"name":"Μαρία 🏋️","handle":"maria.k"}',
    );
  });

  it("falls back to the handle when the name is missing", () => {
    expect(passwordResetNotificationText("password_reset_requested", { person_handle: "@nikos" }, "body", t)).toBe(
      'notifRequestedBody:{"name":"@nikos","handle":"nikos"}',
    );
  });

  it("tells the person their password was reset", () => {
    expect(passwordResetNotificationText("password_reset_completed", {}, "title", t)).toBe("notifCompletedTitle");
    expect(passwordResetNotificationText("password_reset_completed", {}, "body", t)).toBe("notifCompletedBody");
  });

  it("ignores other notifications", () => {
    expect(passwordResetNotificationText("class_workout_missing", {}, "title", t)).toBeNull();
  });
});
