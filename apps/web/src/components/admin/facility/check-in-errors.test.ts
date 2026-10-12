import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { checkInErrorKey, localizeCheckInError } from "@/components/admin/facility/check-in-errors";

const translate = (key: string) => key;

describe("check-in denials", () => {
  it("uses desk wording for open-gym entitlement denials", () => {
    expect(checkInErrorKey(new ApiError(403, "x", { code: "finance_capability_not_included" }))).toBe("admCheckInNoOpenGym");
    expect(checkInErrorKey(new ApiError(403, "x", { code: "finance_allowance_exhausted" }))).toBe("admCheckInAllowanceExhausted");
    expect(checkInErrorKey(new ApiError(403, "x", { code: "finance_membership_frozen" }))).toBe("admCheckInFrozen");
  });

  it("falls back to the shared error messages", () => {
    expect(localizeCheckInError(new ApiError(422, "x", { code: "location_archived" }), translate)).toBe("mbErrLocationArchived");
    expect(localizeCheckInError(new Error("x"), translate)).toBe("apiErrorRequestFailed");
  });
});
