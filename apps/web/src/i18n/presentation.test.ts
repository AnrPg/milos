import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  formatScore,
  localizeAdminAssignmentError,
  localizeError,
  semanticLabel,
} from "@/i18n/presentation";

const translate = vi.fn((key: string, params?: Record<string, unknown>) =>
  params ? `${key}:${JSON.stringify(params)}` : key,
);

describe("semanticLabel", () => {
  it("translates canonical values without changing the stored value", () => {
    expect(semanticLabel("in_progress", translate)).toBe("semanticInProgress");
    expect(semanticLabel("strength", translate)).toBe("semanticStrength");
  });

  it("uses an isolated humanized fallback for extension values", () => {
    expect(semanticLabel("future_state", translate)).toBe("future state");
  });
});

describe("localizeError", () => {
  it("prefers a stable backend error code and interpolation params", () => {
    const error = new ApiError(409, "English compatibility copy", {
      code: "class_type_replacement_required",
      params: { future_class_count: 3 },
    });

    expect(localizeError(error, translate)).toBe(
      'apiErrorClassTypeReplacementRequired:{"future_class_count":3}',
    );
  });

  it("falls back to a localized status category instead of backend prose", () => {
    const error = new ApiError(404, "Not found", {});
    expect(localizeError(error, translate)).toBe("apiErrorNotFound");
  });

  it("uses localized generic copy for non-API failures", () => {
    expect(localizeError(new Error("NetworkError in English"), translate)).toBe(
      "apiErrorRequestFailed",
    );
  });

  it.each([
    ["avatar_storage_unavailable", "apiErrorAvatarStorageUnavailable"],
    ["avatar_upload_missing", "apiErrorAvatarUploadMissing"],
    ["avatar_upload_unverified", "apiErrorAvatarUploadUnverified"],
    ["unsupported_avatar_type", "apiErrorUnsupportedAvatarType"],
    ["avatar_upload_metadata_missing", "apiErrorAvatarUploadMetadataMissing"],
    ["avatar_too_large", "apiErrorAvatarTooLarge"],
    ["avatar_key_forbidden", "apiErrorAvatarKeyForbidden"],
    ["finance_profile_missing", "apiErrorSelfFinanceProfileMissing"],
    ["finance_entitlement_inactive", "apiErrorSelfFinanceEntitlementInactive"],
    ["finance_entitlement_blocked", "apiErrorSelfFinanceEntitlementBlocked"],
    ["finance_entitlement_plan_missing", "apiErrorSelfFinanceEntitlementPlanMissing"],
    ["finance_channel_not_included", "apiErrorSelfFinanceChannelNotIncluded"],
    ["finance_capability_not_included", "apiErrorSelfFinanceCapabilityNotIncluded"],
    ["finance_allowance_not_included", "apiErrorSelfFinanceAllowanceNotIncluded"],
    ["finance_allowance_exhausted", "apiErrorSelfFinanceAllowanceExhausted"],
    ["invalid_athletes", "apiErrorInvalidAthletes"],
    ["workout_not_published", "apiErrorWorkoutNotPublished"],
  ])("gives an actionable assignment message for %s", (code, key) => {
    const error = new ApiError(403, "Compatibility copy", { code });
    expect(localizeError(error, translate)).toBe(key);
  });

  it("uses athlete-specific mitigation in the admin assignment flow", () => {
    const error = new ApiError(403, "Compatibility copy", {
      code: "finance_profile_missing",
    });

    expect(localizeAdminAssignmentError(error, translate)).toBe(
      "apiErrorFinanceProfileMissing",
    );
  });

  it("humanizes entitlement detail parameters for plain users", () => {
    const error = new ApiError(409, "Compatibility copy", {
      code: "finance_allowance_exhausted",
      params: { allowance: "class_visits", limit: 8, committed: 8 },
    });

    expect(localizeError(error, translate)).toBe(
      'apiErrorSelfFinanceAllowanceExhausted:{"allowance":"class visits","limit":8,"committed":8}',
    );
  });
});

describe("formatScore", () => {
  it("turns canonical rounds-and-reps snapshots into localized presentation", () => {
    expect(formatScore("2 rounds + 3 reps", "rounds+reps", undefined, translate)).toBe(
      'scoreRoundsAndReps:{"rounds":2,"reps":3}',
    );
  });

  it("localizes a canonical unit without altering the numeric score", () => {
    expect(formatScore(42, "reps", "reps", translate)).toBe("42 semanticReps");
  });
});
