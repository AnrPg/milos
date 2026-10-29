import { describe, expect, it } from "vitest";
import en from "../../../messages/en.json";
import { FEATURE_SECTIONS } from "./feature-catalog";

describe("FEATURE_SECTIONS", () => {
  it("has unique ids and copy keys that exist in the SiteInfo namespace", () => {
    const ids = FEATURE_SECTIONS.map((section) => section.id);
    expect(new Set(ids).size).toBe(ids.length);
    const siteInfo = (en as Record<string, Record<string, unknown>>).SiteInfo;
    for (const section of FEATURE_SECTIONS) {
      expect(siteInfo[section.titleKey], section.titleKey).toEqual(expect.any(String));
      expect(siteInfo[section.summaryKey], section.summaryKey).toEqual(expect.any(String));
      expect(section.details.length).toBeGreaterThan(0);
    }
  });

  it("lists the structured WOD editor (ADR-270) in the business console", () => {
    const business = FEATURE_SECTIONS.find((section) => section.id === "business");
    expect(business?.details.some((line) => line.startsWith("Structured WOD editor next to free text"))).toBe(true);
  });
});
