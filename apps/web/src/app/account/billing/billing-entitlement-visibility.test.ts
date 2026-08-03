import { describe, expect, it } from "vitest";

import {
  shouldShowAllowanceQuota,
  visibleBillingAllowances,
  visibleBillingChannels,
} from "@/app/account/billing/billing-entitlement-visibility";

describe("customer billing entitlement visibility", () => {
  it("omits benefits that do not have a customer-facing product surface", () => {
    expect(
      visibleBillingChannels([
        "in_person",
        "workout_library",
        "personal_programming",
        "coach_messaging",
      ]),
    ).toEqual(["in_person", "personal_programming", "coach_messaging"]);

    expect(
      visibleBillingAllowances({
        class_visits: { remaining: 4 },
        coaching_touchpoints: { remaining: 10_000 },
      }),
    ).toEqual([["class_visits", { remaining: 4 }]]);
  });

  it("suppresses finite quota copy for unlimited allowances", () => {
    expect(shouldShowAllowanceQuota({ remaining: "unlimited", limit: "unlimited" })).toBe(false);
    expect(shouldShowAllowanceQuota({ remaining: 4, limit: "unlimited" })).toBe(true);
    expect(shouldShowAllowanceQuota({ remaining: "unlimited", limit: 12 })).toBe(true);
  });
});
