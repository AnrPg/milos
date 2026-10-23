import { describe, expect, it } from "vitest";

import { NO_RULES, type StaffPerkInput } from "@/api/perks";

import {
  MAX_CODES_PER_UPLOAD,
  canPublishPerk,
  codesHandedOut,
  emptyPerkDraft,
  localToday,
  normalizePerkCode,
  parsePerkCodes,
  perkDaysLeft,
  perkDraftProblems,
  perkPhase,
  ruleSectionsSet,
} from "./validity";

const draft = (overrides: Partial<StaffPerkInput> = {}): StaffPerkInput => ({
  ...emptyPerkDraft(),
  partner_name: "Nutri Store Κυψέλη",
  benefit_value: 10,
  shared_code: "ΚΥΨΕΛΗ10",
  valid_from: "2026-10-23",
  valid_until: "2026-12-31",
  ...overrides,
});

describe("perk phase", () => {
  it("reads a published perk on the day", () => {
    const perk = { status: "published" as const, valid_from: "2026-11-01", valid_until: "2026-12-31" };
    expect(perkPhase(perk, "2026-10-23")).toBe("scheduled");
    expect(perkPhase(perk, "2026-11-01")).toBe("published");
    expect(perkPhase(perk, "2026-12-31")).toBe("published");
    expect(perkPhase(perk, "2027-01-01")).toBe("expired");
    expect(perkPhase({ ...perk, status: "paused" }, "2026-11-10")).toBe("paused");
    expect(perkPhase({ ...perk, status: "draft" }, "2026-11-10")).toBe("draft");
    expect(perkPhase({ status: "published", valid_from: null, valid_until: null }, "2030-01-01")).toBe("published");
  });

  it("counts the days left, across a month end", () => {
    expect(perkDaysLeft("2026-11-02", "2026-10-30")).toBe(3);
    expect(perkDaysLeft("2026-10-30", "2026-10-30")).toBe(0);
    expect(perkDaysLeft(null, "2026-10-30")).toBeNull();
    expect(localToday(new Date(2026, 0, 5))).toBe("2026-01-05");
  });
});

describe("perk drafts", () => {
  it("accepts a complete draft", () => {
    expect(perkDraftProblems(draft())).toEqual([]);
  });

  it("names what is missing", () => {
    expect(
      perkDraftProblems(
        draft({
          partner_name: " ",
          benefit_value: 120,
          shared_code: "",
          partner_url: "nutri.gr",
          valid_until: "2026-10-01",
          rules: { ...NO_RULES, time_from: "18:00", time_until: null },
          audience: "packages",
          all_locations: false,
          max_claims: 0,
          max_claims_per_member: 0,
        }),
      ),
    ).toEqual(["partnerName", "percent", "code", "partnerUrl", "dates", "hours", "packages", "branches", "maxClaims", "perMember"]);
    expect(perkDraftProblems(draft({ benefit_type: "fixed_amount", benefit_value: 0 }))).toEqual(["amount"]);
    expect(perkDraftProblems(draft({ benefit_type: "free_text", benefit_value: null, benefit_text: "" }))).toEqual(["benefitText"]);
    expect(perkDraftProblems(draft({ benefit_type: "free_text", benefit_value: null, benefit_text: "Δωρεάν shot" }))).toEqual([]);
  });

  it("asks a code only of the methods that hand one out, and a link of the partner link", () => {
    expect(perkDraftProblems(draft({ redemption_method: "qr", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "show_membership", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "unique_code", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link" }))).toEqual(["partnerUrl"]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link", partner_url: "https://nutri.gr/?code=X" }))).toEqual([]);
  });

  it("normalises a typed code to the shape members see", () => {
    expect(normalizePerkCode(" κυψέλη 10 ")).toBe("ΚΥΨΕΛΗ10");
    expect(perkDraftProblems(draft({ shared_code: " palee-10 " }))).toEqual([]);
  });

  it("lets a demo business draft but not publish, and needs free unique codes", () => {
    expect(canPublishPerk(draft(), "demo")).toBe(false);
    expect(canPublishPerk(draft(), "active")).toBe(true);
    const pool = draft({ redemption_method: "unique_code", shared_code: null });
    expect(canPublishPerk(pool, "active", 0)).toBe(false);
    expect(canPublishPerk(pool, "active", 12)).toBe(true);
  });

  it("tells which «Περισσότεροι όροι» sections hold something", () => {
    expect(ruleSectionsSet(draft())).toEqual({ limits: false, when: false, who: false, where: false, terms: false });
    expect(
      ruleSectionsSet(draft({ max_claims: 50, rules: { ...NO_RULES, weekdays: [1, 2], channel: "online" }, audience: "packages", package_ids: ["p"], terms: "Όχι σε προσφορές" })),
    ).toEqual({ limits: true, when: true, who: true, where: true, terms: true });
  });
});

describe("unique code batches", () => {
  it("reads pasted lines and CSV cells, skipping a header and repeats", () => {
    expect(parsePerkCodes('code\nNS-001\nns-002, NS-003;NS-001\n\n"NS-004"\tΑ/Β\n')).toEqual({
      codes: ["NS-001", "NS-002", "NS-003", "NS-004"],
      duplicates: 1,
      invalid: 1,
      tooMany: false,
    });
  });

  it("caps one upload", () => {
    const text = Array.from({ length: MAX_CODES_PER_UPLOAD + 2 }, (_, index) => `C${index}`).join("\n");
    const parsed = parsePerkCodes(text);
    expect(parsed.codes).toHaveLength(MAX_CODES_PER_UPLOAD);
    expect(parsed.tooMany).toBe(true);
  });

  it("counts the codes handed out", () => {
    expect(codesHandedOut({ total: 50, free: 38 })).toBe(12);
  });
});
