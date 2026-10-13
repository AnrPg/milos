import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { classifyDeliveryError, describeOutboxFailure, isAutomaticallyRetryable } from "@/lib/outbox-failure";

const translate = (key: string) => key;

describe("classifyDeliveryError", () => {
  it("keeps network, auth-expiry, throttling, and server errors transient", () => {
    expect(classifyDeliveryError(new TypeError("Failed to fetch"))).toEqual({ category: "transient" });
    for (const status of [401, 408, 425, 429, 500, 503]) {
      expect(classifyDeliveryError(new ApiError(status, "x", {})).category).toBe("transient");
    }
  });

  it("marks 409 as conflict and other client errors as permanent", () => {
    expect(classifyDeliveryError(new ApiError(409, "x", { code: "booking_not_pending" }))).toEqual({
      category: "conflict",
      status: 409,
      code: "booking_not_pending",
    });
    expect(classifyDeliveryError(new ApiError(403, "x", {})).category).toBe("permanent");
    expect(classifyDeliveryError(new ApiError(422, "x", {})).category).toBe("permanent");
  });

  it("lets adapters override by error code", () => {
    const error = new ApiError(422, "x", { code: "custom" });
    expect(classifyDeliveryError(error, { conflictCodes: ["custom"] }).category).toBe("conflict");
  });

  it("only auto-retries transient failures", () => {
    expect(isAutomaticallyRetryable(undefined)).toBe(true);
    expect(isAutomaticallyRetryable({ category: "transient" })).toBe(true);
    expect(isAutomaticallyRetryable({ category: "conflict", status: 409 })).toBe(false);
  });
});

describe("describeOutboxFailure", () => {
  it("maps failures to localized reasons", () => {
    expect(describeOutboxFailure(undefined, translate)).toBe("outboxFailureUnknown");
    expect(describeOutboxFailure({ category: "transient" }, translate)).toBe("outboxFailureNetwork");
    expect(describeOutboxFailure({ category: "transient", status: 401 }, translate)).toBe(
      "outboxFailureSessionExpired",
    );
    expect(describeOutboxFailure({ category: "conflict", status: 409 }, translate)).toBe(
      "outboxFailureConflict",
    );
    expect(
      describeOutboxFailure({ category: "permanent", code: "unsupported_operation" }, translate),
    ).toBe("outboxFailureUnsupported");
  });

  it("uses the API error catalog for known codes and statuses", () => {
    expect(describeOutboxFailure({ category: "conflict", status: 409, code: "slot_full" }, translate)).toBe(
      "mbErrSlotFull",
    );
    expect(
      describeOutboxFailure({ category: "conflict", status: 409, code: "booking_not_pending" }, translate),
    ).toBe("apiErrorBookingNotPending");
    expect(describeOutboxFailure({ category: "permanent", status: 403 }, translate)).toBe(
      "apiErrorForbidden",
    );
  });
});
