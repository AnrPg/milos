import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { EffectiveEntitlement } from "@/api/my-finance";
import {
  allowanceRemaining,
  cancellationCutoffHours,
  entitledFeatures,
  hasCapability,
  hasFeature,
  isNotEntitledError,
  responseSlaHours,
} from "@/components/client/entitlement";

function entitlement(capabilities: string[], terms: Record<string, unknown> = {}): EffectiveEntitlement {
  return {
    status: "active",
    enforcement_mode: "enforce",
    plan: { entitlement_version: 2, channels: [], capabilities, terms },
    allowances: {
      form_reviews: {
        limit: 4,
        period: "calendar_month",
        period_start: "2026-10-01",
        period_end: "2026-10-31",
        committed: 1,
        extensions: 0,
        remaining: 3,
      },
    },
    usage_entries: [],
  };
}

describe("client entitlement gating", () => {
  it("hides every feature without a plan", () => {
    expect(entitledFeatures(null)).toEqual([]);
    expect(entitledFeatures({ ...entitlement([]), plan: null })).toEqual([]);
    expect(hasCapability(undefined, "watch_on_demand")).toBe(false);
  });

  it("maps capabilities to features, any capability unlocking a shared page", () => {
    expect(entitledFeatures(entitlement(["watch_on_demand", "book_assessments"]))).toEqual([
      "videos",
      "appointments",
    ]);
    expect(hasFeature(entitlement(["receive_nutrition_plan"]), "coaching")).toBe(true);
    expect(hasFeature(entitlement(["request_form_reviews"]), "coaching")).toBe(true);
    expect(hasFeature(entitlement(["book_pt_sessions"]), "progress")).toBe(false);
    expect(entitledFeatures(entitlement(["view_advanced_analytics"]))).toEqual(["progress"]);
  });

  it("treats only 403 API errors as not entitled", () => {
    expect(isNotEntitledError(new ApiError(403, "no", { code: "finance_capability_not_included" }))).toBe(true);
    expect(isNotEntitledError(new ApiError(500, "boom", {}))).toBe(false);
    expect(isNotEntitledError(new Error("x"))).toBe(false);
  });

  it("reads response time, cancellation cutoff and remaining allowance from terms", () => {
    const value = entitlement([], { response_sla_hours: 24, cancellation_cutoff_hours: 12 });
    expect(responseSlaHours(value)).toBe(24);
    expect(cancellationCutoffHours(value)).toBe(12);
    expect(responseSlaHours(entitlement([], { response_sla_hours: null }))).toBeNull();
    expect(cancellationCutoffHours(entitlement([], { cancellation_cutoff_hours: 0 }))).toBeNull();
    expect(allowanceRemaining(value, "form_reviews")).toEqual({ remaining: 3, limit: 4 });
    expect(allowanceRemaining(value, "pt_sessions")).toBeNull();
  });
});
