import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";

import { signOutLinkFailure } from "./sign-out-link";

describe("signOutLinkFailure", () => {
  it("reads the API's link codes", () => {
    expect(signOutLinkFailure(new ApiError(410, "gone", { code: "expired_link" }))).toBe("expired");
    expect(signOutLinkFailure(new ApiError(410, "gone", { code: "used_link" }))).toBe("used");
    expect(signOutLinkFailure(new ApiError(422, "bad", { code: "invalid_link" }))).toBe("invalid");
  });

  it("leaves anything else to the generic error", () => {
    expect(signOutLinkFailure(new ApiError(500, "boom", {}))).toBe("other");
    expect(signOutLinkFailure(new Error("offline"))).toBe("other");
  });
});
