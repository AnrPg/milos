import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { deletionFailure, deletionLinkFailure } from "@/components/account/account-deletion-model";

const apiError = (status: number, payload: Record<string, unknown>) =>
  new ApiError(status, "refused", payload as never);

describe("deletionFailure (ADR-211)", () => {
  it("maps the refusals the Settings dialog explains", () => {
    expect(deletionFailure(apiError(422, { code: "invalid_password" }))).toEqual({ key: "errorPassword" });
    expect(deletionFailure(apiError(422, { code: "confirmation_mismatch" }))).toEqual({ key: "errorConfirmation" });
    expect(deletionFailure(apiError(409, { code: "already_scheduled" }))).toEqual({ key: "errorScheduled" });
  });

  it("names the businesses a sole owner must hand over", () => {
    expect(
      deletionFailure(apiError(409, { code: "sole_owner", organizations: ["Box Kypseli", 7, "Coach Maria"] })),
    ).toEqual({ key: "errorSoleOwner", values: { names: "«Box Kypseli», «Coach Maria»" } });
  });

  it("leaves anything else to the generic error", () => {
    expect(deletionFailure(apiError(500, { code: "boom" }))).toBeNull();
    expect(deletionFailure(new Error("offline"))).toBeNull();
  });
});

describe("deletionLinkFailure", () => {
  it("tells an expired link from an invalid one", () => {
    expect(deletionLinkFailure(apiError(410, { code: "expired_deletion_link" }))).toBe("expired");
    expect(deletionLinkFailure(apiError(422, { code: "invalid_deletion_link" }))).toBe("invalid");
    expect(deletionLinkFailure(apiError(503, {}))).toBe("other");
    expect(deletionLinkFailure("nope")).toBe("other");
  });
});
