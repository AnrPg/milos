import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { formatScore, localizeError, semanticLabel } from "@/i18n/presentation";

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
