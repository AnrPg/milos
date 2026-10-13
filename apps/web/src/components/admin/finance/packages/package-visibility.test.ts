import { describe, expect, it } from "vitest";

import catalogJson from "./__fixtures__/package-catalog.json";
import { newDraft, type PackageCatalog } from "./package-catalog";
import { phaseCFieldVisible, sectionVisible, withDependents } from "./package-ui";

const catalog = catalogJson as unknown as PackageCatalog;
const withModules = (...keys: string[]): PackageCatalog => ({
  ...catalog,
  modules: catalog.modules.map((module) => (keys.includes(module.key) ? { ...module, enabled: true } : module)),
});

describe("Phase C field visibility (ADR-098)", () => {
  it("shows personal training and content only when their module is on or the draft uses them", () => {
    const draft = newDraft(catalog, "membership");
    expect(sectionVisible("personal_training", draft, catalog)).toBe(false);
    expect(sectionVisible("content", draft, catalog)).toBe(false);
    expect(sectionVisible("personal_training", draft, withModules("personal_training"))).toBe(true);
    expect(sectionVisible("content", draft, withModules("digital_content"))).toBe(true);

    draft.fields["content.advanced_analytics"] = true;
    expect(sectionVisible("content", draft, catalog)).toBe(true);
    // The trial preset's assessment alone does not open the section without the module.
    const trial = newDraft(catalog, "trial");
    expect(sectionVisible("personal_training", trial, catalog)).toBe(false);
    expect(sectionVisible("personal_training", trial, withModules("personal_training"))).toBe(true);
    trial.fields["personal_training.included"] = true;
    expect(sectionVisible("personal_training", trial, catalog)).toBe(true);
  });

  it("shows trainer details only with personal training, and group size only for semi-private", () => {
    const draft = newDraft(catalog, "membership");
    expect(phaseCFieldVisible("personal_training.sessions", draft)).toBe(false);
    expect(phaseCFieldVisible("personal_training.assessments", draft)).toBe(true);
    draft.fields["personal_training.included"] = true;
    expect(phaseCFieldVisible("personal_training.coach_id", draft)).toBe(true);
    expect(phaseCFieldVisible("personal_training.group_size", draft)).toBe(false);
    draft.fields["personal_training.format"] = "semi_private";
    expect(phaseCFieldVisible("personal_training.group_size", draft)).toBe(true);
  });

  it("shows payment-model terms only for their type", () => {
    const membership = newDraft(catalog, "membership");
    for (const key of ["terms.compatible_package_ids", "terms.beneficiaries", "terms.seats", "terms.enrollment_domain"]) {
      expect(phaseCFieldVisible(key, membership)).toBe(false);
    }
    expect(phaseCFieldVisible("terms.compatible_package_ids", newDraft(catalog, "add_on"))).toBe(true);
    expect(phaseCFieldVisible("terms.quota_sharing", newDraft(catalog, "shared"))).toBe(true);
    const corporate = newDraft(catalog, "corporate");
    expect(phaseCFieldVisible("terms.seat_billing", corporate)).toBe(true);
    expect(phaseCFieldVisible("terms.enrollment_domain", corporate)).toBe(false);
    corporate.fields["terms.enrollment"] = "email_domain";
    expect(phaseCFieldVisible("terms.enrollment_domain", corporate)).toBe(true);
  });

  it("resets the group size when the format changes", () => {
    const draft = newDraft(catalog, "pt_pack");
    expect(withDependents("personal_training.format", "semi_private", draft)).toEqual([
      ["personal_training.format", "semi_private"],
      ["personal_training.group_size", 2],
    ]);
    expect(withDependents("personal_training.sessions", { limit: 5, period: "subscription_period" }, draft)).toHaveLength(1);
  });
});
