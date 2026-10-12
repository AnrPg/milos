import { describe, expect, it } from "vitest";

import catalogJson from "./__fixtures__/package-catalog.json";
import {
  applyLocks,
  changeBillingPeriod,
  changedFields,
  draftFromPackage,
  draftIssues,
  fieldLabelKey,
  findType,
  isPartLocked,
  memberSummary,
  newDraft,
  perVisitCents,
  presetFor,
  resetAll,
  selectableTypes,
  switchType,
  toPackageRequest,
  wizardSteps,
  type PackageCatalog,
} from "./package-catalog";

// Exported from the backend's PackageCatalogDocument so presets and locks are never duplicated.
const catalog = catalogJson as unknown as PackageCatalog;

describe("package catalog helpers", () => {
  it("offers only implemented and enabled types", () => {
    expect(selectableTypes(catalog).map((type) => type.key)).toEqual(["membership", "class_pack", "drop_in", "trial"]);
  });

  it("starts drafts from the preset with locks applied", () => {
    const dropIn = newDraft(catalog, "drop_in");
    expect(dropIn.billingPeriod).toBe("one_off");
    expect(dropIn.fields["group_classes.visits"]).toEqual({ limit: 1, period: "subscription_period" });
    expect(newDraft(catalog, "trial").price).toBe("0");
  });

  it("re-applies locks so locked parts cannot drift", () => {
    const type = findType(catalog, "class_pack")!;
    const fields = applyLocks(type, { ...type.preset, "group_classes.visits": { limit: 20, period: "calendar_month" } });
    expect(fields["group_classes.visits"]).toEqual({ limit: 20, period: "subscription_period" });
    expect(isPartLocked(type, "group_classes.visits", "period")).toBe(true);
    expect(isPartLocked(type, "group_classes.visits", "limit")).toBe(false);
  });

  it("keeps the basics when switching type", () => {
    const draft = { ...newDraft(catalog, "membership"), name: "Ten", price: "90" };
    const switched = switchType(catalog, draft, "class_pack");
    expect(switched.name).toBe("Ten");
    expect(switched.price).toBe("90");
    expect(switched.fields["terms.auto_renew"]).toBe(false);
  });

  it("updates period-dependent suggestions only when untouched", () => {
    const type = findType(catalog, "membership")!;
    const annual = changeBillingPeriod(type, newDraft(catalog, "membership"), "annual");
    expect(annual.fields["perks.freeze_days_per_year"]).toBe(30);
  });

  it("reports changes against the preset and resets them", () => {
    const draft = newDraft(catalog, "membership");
    const edited = { ...draft, fields: { ...draft.fields, "terms.auto_renew": false } };
    expect(changedFields(catalog, edited)).toEqual(["terms.auto_renew"]);
    expect(changedFields(catalog, resetAll(catalog, edited))).toEqual([]);
  });

  it("validates basics and services before submitting", () => {
    const draft = newDraft(catalog, "membership");
    expect(draftIssues(draft).map((issue) => issue.field)).toEqual(["name", "price"]);
    const noService = { ...draft, name: "X", price: "10", fields: { ...draft.fields, "group_classes.included": false } };
    expect(draftIssues(noService).map((issue) => issue.message)).toEqual(["pkgErrorServiceRequired"]);
  });

  it("sends only implemented fields", () => {
    const draft = { ...newDraft(catalog, "class_pack"), name: " Ten visits ", price: "99,50" };
    const request = toPackageRequest(catalog, draft);
    expect(request).toMatchObject({ name: "Ten visits", package_type: "class_pack", billing_period: "one_off", base_price_cents: 9950 });
    expect(Object.keys(request.fields)).toContain("group_classes.visits");
    expect(Object.keys(request.fields)).not.toContain("personal_training.assessments");
    expect(perVisitCents(draft)).toBe(995);
  });

  it("round-trips a stored package into a draft", () => {
    const draft = draftFromPackage(catalog, {
      name: "Monthly",
      package_type: "membership",
      billing_period: "quarterly",
      base_price_cents: 15000,
      fields: findType(catalog, "membership")!.preset,
    });
    expect(draft.price).toBe("150");
    expect(draft.billingPeriod).toBe("quarterly");
  });

  it("describes the package for members", () => {
    const draft = newDraft(catalog, "class_pack");
    const lines = memberSummary(draft, new Map());
    expect(lines[0]).toEqual({ key: "pkgSummaryVisitsTotal", params: { count: 10 } });
    expect(lines.map((line) => line.key)).toContain("pkgSummaryValidity_month");
  });

  it("derives message keys and steps", () => {
    expect(fieldLabelKey("group_classes.class_type_limits")).toBe("pkgFieldGroupClassesClassTypeLimits");
    expect(wizardSteps("drop_in")).toEqual(["type", "basics", "review"]);
    expect(wizardSteps("membership")).toHaveLength(4);
  });

  it("names class types without restrictive wording and lists only changed advanced values", () => {
    const draft = newDraft(catalog, "membership");
    const type = findType(catalog, "membership")!;
    const preset = presetFor(type, draft.billingPeriod);
    draft.fields["group_classes.class_types"] = ["ct-1"];
    const keys = (lines: ReturnType<typeof memberSummary>) => lines.map((line) => line.key);

    const plain = memberSummary(draft, new Map([["ct-1", "Yoga"]]), preset);
    expect(plain).toContainEqual({ key: "pkgSummaryClassTypesList", params: { names: "Yoga" } });
    expect(keys(plain)).not.toContain("pkgSummaryWaitlistPriority");

    draft.fields["booking.waitlist_priority"] = "high";
    draft.fields["perks.guest_passes"] = { limit: 2, period: "calendar_month" };
    draft.fields["perks.member_discount_percent"] = 10;
    const extended = keys(memberSummary(draft, new Map(), preset));
    expect(extended).toEqual(expect.arrayContaining(["pkgSummaryWaitlistPriority", "pkgSummaryGuestPasses_calendar_month", "pkgSummaryDiscount"]));
  });
});
