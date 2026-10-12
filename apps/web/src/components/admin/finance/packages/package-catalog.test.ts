import { describe, expect, it } from "vitest";

import catalogJson from "./__fixtures__/package-catalog.json";
import {
  anyServiceIncluded,
  applyLocks,
  changeBillingPeriod,
  changedFields,
  draftFromPackage,
  draftIssues,
  fieldLabelKey,
  findType,
  groupSizeForFormat,
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
    // PT packs and corporate plans need their module; the catalog reports them as not enabled.
    expect(selectableTypes(catalog).map((type) => type.key)).toEqual(["membership", "class_pack", "drop_in", "trial", "add_on", "shared"]);
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
    expect(Object.keys(request.fields)).toContain("personal_training.assessments");
    expect(Object.keys(request.fields)).not.toContain("content.workout_library");
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

describe("Phase C packages (ADR-098)", () => {
  const keys = (lines: ReturnType<typeof memberSummary>) => lines.map((line) => line.key);
  const withType = (typeKey: string) => {
    // Disabled types (pt_pack, corporate) are still valid drafts for stored packages.
    return newDraft(catalog, typeKey);
  };

  it("describes personal training sessions, coach and assessments", () => {
    const draft = withType("pt_pack");
    const lines = memberSummary(draft, new Map(), null, undefined, { coachName: "Maria" });
    expect(lines).toContainEqual({
      key: "pkgSummaryPtSessions_subscription_period",
      params: { count: 10, minutes: 60, format: "one_to_one", size: 1 },
    });
    expect(lines).toContainEqual({ key: "pkgSummaryAssessments", params: { count: 1 } });
    expect(keys(lines)).not.toContain("pkgSummaryPtCoach");

    draft.fields["personal_training.coach_id"] = "coach-1";
    draft.fields["personal_training.format"] = "semi_private";
    draft.fields["personal_training.group_size"] = 3;
    draft.fields["personal_training.session_minutes"] = 45;
    const named = memberSummary(draft, new Map(), null, undefined, { coachName: "Maria" });
    expect(named).toContainEqual({ key: "pkgSummaryPtCoach", params: { name: "Maria" } });
    expect(named).toContainEqual({
      key: "pkgSummaryPtSessions_subscription_period",
      params: { count: 10, minutes: 45, format: "semi_private", size: 3 },
    });
    expect(keys(memberSummary(draft, new Map()))).toContain("pkgSummaryPtCoachAssigned");
  });

  it("describes coaching extras and digital content", () => {
    const draft = newDraft(catalog, "membership");
    Object.assign(draft.fields, {
      "online_coaching.included": true,
      "online_coaching.form_reviews": { limit: 2, period: "calendar_month" },
      "online_coaching.response_sla_hours": 24,
      "online_coaching.nutrition_plan": true,
      "content.on_demand_video": true,
      "content.advanced_analytics": true,
    });
    const lines = memberSummary(draft, new Map());
    expect(lines).toContainEqual({ key: "pkgSummaryFormReviews_calendar_month", params: { count: 2 } });
    expect(lines).toContainEqual({ key: "pkgSummaryResponseSla", params: { hours: 24 } });
    expect(keys(lines)).toEqual(expect.arrayContaining(["pkgSummaryNutritionPlan", "pkgSummaryOnDemandVideo", "pkgSummaryAdvancedAnalytics"]));

    // Form reviews and reply times belong to coaching; the nutrition plan stands alone.
    draft.fields["online_coaching.included"] = false;
    const without = keys(memberSummary(draft, new Map()));
    expect(without).not.toContain("pkgSummaryFormReviews_calendar_month");
    expect(without).not.toContain("pkgSummaryResponseSla");
    expect(without).toContain("pkgSummaryNutritionPlan");
  });

  it("advertises preset assessments only when personal training is offered", () => {
    const trial = newDraft(catalog, "trial");
    expect(keys(memberSummary(trial, new Map(), null, undefined, { showAssessments: true }))).toContain("pkgSummaryAssessments");
    expect(keys(memberSummary(trial, new Map(), null, undefined, { showAssessments: false }))).not.toContain("pkgSummaryAssessments");
  });

  it("never describes the retired workout library", () => {
    const draft = newDraft(catalog, "membership");
    draft.fields["content.workout_library"] = true;
    expect(keys(memberSummary(draft, new Map())).some((key) => key.toLowerCase().includes("library"))).toBe(false);
  });

  it("describes add-on, shared and company plans", () => {
    const addOn = withType("add_on");
    addOn.fields["terms.compatible_package_ids"] = ["m-1"];
    const addOnLines = memberSummary(addOn, new Map(), null, undefined, { compatibleNames: ["Unlimited"] });
    expect(addOnLines[0]).toEqual({ key: "pkgSummaryAddOn" });
    expect(addOnLines).toContainEqual({ key: "pkgSummaryAddOnFor", params: { names: "Unlimited" } });
    expect(keys(addOnLines)).toContain("pkgSummaryNutritionPlan");

    const shared = withType("shared");
    shared.fields["terms.quota_sharing"] = "shared";
    shared.fields["terms.allow_minor_beneficiaries"] = true;
    const sharedLines = memberSummary(shared, new Map());
    expect(sharedLines).toContainEqual({ key: "pkgSummaryShared", params: { count: 2 } });
    expect(keys(sharedLines)).toEqual(expect.arrayContaining(["pkgSummaryQuotaShared", "pkgSummaryMinorsAllowed"]));

    const corporate = withType("corporate");
    expect(keys(memberSummary(corporate, new Map()))).toEqual(expect.arrayContaining(["pkgSummaryCorporate", "pkgSummaryEnrollCode"]));
    corporate.fields["terms.enrollment"] = "email_domain";
    corporate.fields["terms.enrollment_domain"] = "acme.gr";
    expect(memberSummary(corporate, new Map())).toContainEqual({ key: "pkgSummaryEnrollDomain", params: { domain: "acme.gr" } });
  });

  it("counts Phase C services and checks payment-model rules", () => {
    expect(anyServiceIncluded({ "content.on_demand_video": true })).toBe(true);
    expect(anyServiceIncluded({ "online_coaching.nutrition_plan": true })).toBe(true);
    expect(anyServiceIncluded({ "personal_training.included": true })).toBe(true);

    const add = { ...withType("add_on"), name: "Nutrition", price: "20" };
    expect(draftIssues(add)).toEqual([]);

    const shared = { ...withType("shared"), name: "Couple", price: "90" };
    shared.fields["terms.beneficiaries"] = 1;
    expect(draftIssues(shared).map((issue) => issue.message)).toEqual(["pkgErrorBeneficiariesMin"]);

    const corporate = { ...withType("corporate"), name: "Acme", price: "500" };
    corporate.fields["terms.enrollment"] = "email_domain";
    expect(draftIssues(corporate).map((issue) => issue.field)).toEqual(["terms.enrollment_domain"]);

    const membership = { ...withType("membership"), name: "PT", price: "100" };
    membership.fields["personal_training.included"] = true;
    expect(draftIssues(membership).map((issue) => issue.message)).toEqual(["pkgErrorSessionsPositive"]);
  });

  it("keeps the group size valid for the session format", () => {
    expect(groupSizeForFormat("one_to_one", 3)).toBe(1);
    expect(groupSizeForFormat("semi_private", 1)).toBe(2);
    expect(groupSizeForFormat("semi_private", 4)).toBe(4);
  });

  it("prices PT packs per session", () => {
    const draft = { ...withType("pt_pack"), price: "400" };
    expect(perVisitCents(draft)).toBe(4000);
  });
});
