import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { describeEmailChangeError, emailChangeLinkFailure } from "@/components/account/email-change-model";

const apiError = (status: number, payload: Record<string, unknown>) => new ApiError(status, "failed", payload);

describe("describeEmailChangeError", () => {
  it("maps the API's refusals to emailChange messages", () => {
    expect(describeEmailChangeError(apiError(422, { code: "invalid_current_password" }))).toEqual({
      key: "errors.currentPassword",
    });
    expect(describeEmailChangeError(apiError(422, { code: "invalid_email" }))).toEqual({ key: "errors.invalidEmail" });
    expect(describeEmailChangeError(apiError(422, { code: "email_unchanged" }))).toEqual({ key: "errors.unchanged" });
    expect(describeEmailChangeError(apiError(422, { code: "suppressed" }))).toEqual({ key: "errors.suppressed" });
    expect(describeEmailChangeError(apiError(429, {}))).toEqual({ key: "errors.throttled" });
    expect(describeEmailChangeError(apiError(404, { code: "no_pending_email_change" }))).toEqual({
      key: "errors.nothingPending",
    });
  });

  it("names the date a lock ends, when the API gives one", () => {
    expect(
      describeEmailChangeError(
        apiError(409, { code: "email_change_locked", locked_until: "2026-12-31T10:00:00Z" }),
      ),
    ).toEqual({ key: "errors.lockedUntil", values: { date: new Date("2026-12-31T10:00:00Z") } });
    expect(describeEmailChangeError(apiError(409, { code: "email_change_locked" }))).toEqual({ key: "errors.locked" });
  });

  it("leaves anything else to the generic error text", () => {
    expect(describeEmailChangeError(apiError(500, {}))).toBeNull();
    expect(describeEmailChangeError(new Error("offline"))).toBeNull();
  });
});

describe("emailChangeLinkFailure", () => {
  it("tells expired, used and taken links apart", () => {
    expect(emailChangeLinkFailure(apiError(410, { code: "expired_email_change_link" }))).toBe("expired");
    expect(emailChangeLinkFailure(apiError(422, { code: "invalid_email_change_link" }))).toBe("invalid");
    expect(emailChangeLinkFailure(apiError(409, { code: "email_change_unavailable" }))).toBe("unavailable");
    expect(emailChangeLinkFailure(apiError(500, {}))).toBe("other");
    expect(emailChangeLinkFailure(new Error("offline"))).toBe("other");
  });
});
