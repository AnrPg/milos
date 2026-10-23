import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import {
  handleInput,
  passwordLongEnough,
  registerFailure,
  resetFailure,
  resetTokenFromHash,
  type Translate,
} from "@/components/auth/auth-errors";

const t: Translate = (key, values) => (values ? `${key}:${JSON.stringify(values)}` : key);
const fallback = () => "fallback";

describe("registerFailure", () => {
  it("shows how many of the allowed accounts an email already has, under the email field", () => {
    const error = new ApiError(409, "This email already has accounts", {
      code: "email_in_use",
      profile_count: 2,
      profile_limit: 3,
      errors: { email: ["already has accounts"] },
    } as never);

    expect(registerFailure(error, t, fallback, "generic")).toEqual({
      fieldErrors: { email: ['emailInUseCount:{"count":2,"limit":3} emailInUseAddProfile'] },
      message: null,
    });
  });

  it("says the limit is reached when the email holds the most accounts", () => {
    const error = new ApiError(409, "", { code: "email_in_use", profile_count: 3, profile_limit: 3 } as never);
    expect(registerFailure(error, t, fallback, "generic").fieldErrors.email).toEqual(['emailLimitReached:{"limit":3}']);
  });

  it("falls back to a countless message when the API gives no count", () => {
    const error = new ApiError(409, "", { code: "email_in_use" });
    expect(registerFailure(error, t, fallback, "generic").fieldErrors.email).toEqual(["emailInUseUnknown"]);
  });

  it("maps profile_limit to the limit message", () => {
    const error = new ApiError(422, "", { code: "profile_limit", profile_limit: 3 } as never);
    expect(registerFailure(error, t, fallback, "generic").fieldErrors.email).toEqual(['emailLimitReached:{"limit":3}']);
  });

  it("puts validation errors under their fields", () => {
    const error = new ApiError(422, "", {
      errors: {
        handle: ["has already been taken"],
        display_name: ["must be 1-50 characters"],
        email: ["must be a valid email address"],
        password: ["should be at least 4 character(s)"],
        role: ["is invalid"],
      },
    });

    expect(registerFailure(error, t, fallback, "generic")).toEqual({
      fieldErrors: {
        handle: ["handleTakenError"],
        display_name: ["displayNameRule"],
        email: ["emailInvalid"],
        password: ["passwordRule"],
        role: ["generic"],
      },
      message: null,
    });
  });

  it("reads the deprecated nickname field as the handle", () => {
    const error = new ApiError(422, "", { errors: { nickname: ["must be 3-30 Latin letters"] } });
    expect(registerFailure(error, t, fallback, "generic").fieldErrors).toEqual({ handle: ["handleRule"] });
  });

  it("leaves other failures to the fallback", () => {
    expect(registerFailure(new ApiError(401, "", { code: "invalid_credentials" }), t, fallback, "generic")).toEqual({
      fieldErrors: {},
      message: "fallback",
    });
    expect(registerFailure(new Error("offline"), t, fallback, "generic").message).toBe("fallback");
  });
});

describe("resetFailure", () => {
  it("tells expired, invalid and weak-password answers apart", () => {
    expect(resetFailure(new ApiError(410, "", { code: "expired_reset_link" }))).toBe("expired");
    expect(resetFailure(new ApiError(422, "", { code: "invalid_reset_link" }))).toBe("invalid");
    expect(resetFailure(new ApiError(422, "", { code: "weak_password" }))).toBe("weak_password");
    expect(resetFailure(new ApiError(500, "", {}))).toBe("other");
    expect(resetFailure(new Error("offline"))).toBe("other");
  });
});

describe("resetTokenFromHash", () => {
  it("reads the token from the fragment", () => {
    expect(resetTokenFromHash("#token=abc_DEF-123")).toBe("abc_DEF-123");
    expect(resetTokenFromHash("token=abc")).toBe("abc");
  });

  it("returns null without a token", () => {
    expect(resetTokenFromHash("")).toBeNull();
    expect(resetTokenFromHash("#token=")).toBeNull();
    expect(resetTokenFromHash("#other=1")).toBeNull();
  });
});

describe("handleInput", () => {
  it("drops a typed @ and spaces", () => {
    expect(handleInput("@maria k")).toBe("mariak");
    expect(handleInput("@@Μαρία")).toBe("Μαρία");
  });
});

describe("passwordLongEnough", () => {
  it("needs 4 characters that are not whitespace", () => {
    expect(passwordLongEnough("1537")).toBe(true);
    expect(passwordLongEnough("a b c d")).toBe(true);
    expect(passwordLongEnough("καλή")).toBe(true);
    expect(passwordLongEnough(" 1 2 3 ")).toBe(false);
    expect(passwordLongEnough("    ")).toBe(false);
  });
});
