import { describe, expect, it } from "vitest";

import { applied, crossfit, plan } from "./fixtures";
import { appliedCounts, changedPrices, formatPrice, parsePrice, previewOf } from "./recipe-model";

describe("previewOf", () => {
  it("splits the plan into packages with their period, class types, worded rules and the rest", () => {
    const preview = previewOf(plan, crossfit);
    expect(preview.packages).toEqual([
      { code: "setup_unlimited", name: "Unlimited", cents: 7500, period: "monthly" },
      { code: "setup_trial", name: "Trial", cents: 1000, period: "none" },
    ]);
    expect(preview.classTypes).toEqual(["CrossFit", "Open gym"]);
    expect(preview.rules.map((rule) => rule.key)).toEqual([
      "scheduling.default_auto_approve",
      "scheduling.default_booking_window_days",
      "scheduling.default_cancellation_cutoff_minutes",
    ]);
    expect(preview.advanced).toBe(1);
  });
});

describe("prices", () => {
  it("reads whole and decimal amounts with a comma or a dot", () => {
    expect(parsePrice("75")).toBe(7500);
    expect(parsePrice("75,50")).toBe(7550);
    expect(parsePrice(" 75.5 ")).toBe(7550);
    expect(parsePrice("")).toBeNull();
    expect(parsePrice("-3")).toBeNull();
    expect(parsePrice("7,555")).toBeNull();
    expect(formatPrice(7500)).toBe("75");
    expect(formatPrice(7550)).toBe("75.50");
  });

  it("sends only the prices the owner changed, or names the wrong ones", () => {
    const { packages } = previewOf(plan, crossfit);
    expect(changedPrices(packages, {})).toEqual({ prices: {} });
    expect(changedPrices(packages, { setup_unlimited: "80", setup_trial: "10" })).toEqual({ prices: { setup_unlimited: 8000 } });
    expect(changedPrices(packages, { setup_unlimited: "eighty" })).toEqual({ invalid: ["setup_unlimited"] });
  });
});

describe("appliedCounts", () => {
  it("counts packages, class types and rules of the applied recipe", () => {
    expect(appliedCounts(applied)).toEqual({ packages: 2, classTypes: 2, rules: 4 });
  });
});
