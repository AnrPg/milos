import { describe, expect, it } from "vitest";

import type { StaffPerk } from "@/api/perks";

import {
  MAX_CODES_PER_UPLOAD,
  canPublishPerk,
  codesHandedOut,
  draftFromPerk,
  emptyPerkDraft,
  localToday,
  methodNeedsCode,
  normalizePerkCode,
  parsePerkCodes,
  perkDaysLeft,
  perkDraftProblems,
  perkPhase,
  ruleSectionsSet,
  toPerkInput,
  type PerkDraft,
} from "./validity";

const draft = (overrides: Partial<PerkDraft> = {}): PerkDraft => ({
  ...emptyPerkDraft(),
  partner_name: "Nutri Store Κυψέλη",
  percent: 10,
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
          percent: 120,
          shared_code: "",
          partner_url: "nutri.gr",
          valid_until: "2026-10-01",
          windows: [{ weekdays: [1], from: "18:00", until: "09:00" }],
          audience: "packages",
          all_locations: false,
          max_claims: 0,
          max_per_member: 0,
          period: "week",
          min_tenure_days: 0,
        }),
      ),
    ).toEqual(["partnerName", "percent", "code", "partnerUrl", "dates", "windows", "packages", "branches", "maxClaims", "perMember", "period", "tenure"]);
    expect(perkDraftProblems(draft({ benefit_type: "fixed_amount", amount_cents: 0 }))).toEqual(["amount"]);
    expect(perkDraftProblems(draft({ benefit_type: "free_item", item: " " }))).toEqual(["item"]);
    expect(perkDraftProblems(draft({ benefit_type: "buy_x_get_y", buy_quantity: 2, get_quantity: null }))).toEqual(["quantities"]);
    expect(perkDraftProblems(draft({ benefit_type: "free_text", text: "" }))).toEqual(["benefitText"]);
    expect(perkDraftProblems(draft({ benefit_type: "free_text", text: "Δωρεάν shot" }))).toEqual([]);
    expect(perkDraftProblems(draft({ windows: [{ weekdays: [], from: "06:00", until: "10:00" }] }))).toEqual(["windows"]);
  });

  it("asks a code only where the method hands one out, and an https link of the partner link", () => {
    expect(perkDraftProblems(draft({ redemption_method: "personal_qr", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "show_membership", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "code_pool", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link" }))).toEqual(["linkUrl"]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link", link_url: "http://nutri.gr" }))).toEqual(["linkUrl"]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link", link_url: "https://nutri.gr/offer", shared_code: null }))).toEqual([]);
    expect(perkDraftProblems(draft({ redemption_method: "partner_link", link_url: "https://nutri.gr/?c={code}", shared_code: null }))).toEqual(["code"]);
    expect(methodNeedsCode("partner_link", "https://nutri.gr/?c={code}")).toBe(true);
    expect(methodNeedsCode("code_pool", null)).toBe(false);
  });

  it("normalises a typed code to the shape members see", () => {
    expect(normalizePerkCode(" κυψέλη 10 ")).toBe("ΚΥΨΕΛΗ10");
    expect(perkDraftProblems(draft({ shared_code: " palee-10 " }))).toEqual([]);
  });

  it("lets a demo business draft but not publish, and needs free pool codes", () => {
    expect(canPublishPerk(draft(), "demo")).toBe(false);
    expect(canPublishPerk(draft(), "active")).toBe(true);
    const pool = draft({ redemption_method: "code_pool", shared_code: null });
    expect(canPublishPerk(pool, "active", 0)).toBe(false);
    expect(canPublishPerk(pool, "active", 12)).toBe(true);
  });

  it("tells which «Περισσότεροι όροι» sections hold something", () => {
    expect(ruleSectionsSet(draft())).toEqual({ limits: false, when: false, who: false, where: false, terms: false });
    expect(
      ruleSectionsSet(
        draft({
          max_claims: 50,
          windows: [{ weekdays: [1, 2], from: "06:00", until: "10:00" }],
          channel: "online",
          audience: "packages",
          package_ids: ["p"],
          terms: "Όχι σε προσφορές",
        }),
      ),
    ).toEqual({ limits: true, when: true, who: true, where: true, terms: true });
  });
});

describe("the API documents", () => {
  it("sends only the fields a benefit type uses, the windows in full time and the method's settings", () => {
    const input = toPerkInput(
      draft({
        partner_name: "  Nutri  ",
        text: " σε όλα ",
        max_discount_cents: 2000,
        windows: [{ weekdays: [3, 1], from: "06:00", until: "10:00" }],
        period: "month",
        max_per_member_per_period: 1,
        audience: "all_clients",
        package_ids: ["stale"],
        shared_code: "nutri 10",
        link_url: "https://ignored",
      }),
    );
    expect(input.partner_name).toBe("Nutri");
    expect(input.benefit).toEqual({ type: "percent", percent: 10, max_discount_cents: 2000, text: "σε όλα", min_spend_cents: null });
    expect(input.rules.recurring).toEqual([{ weekdays: [1, 3], starts_at: "06:00:00", ends_at: "10:00:00" }]);
    expect(input.rules.limits).toEqual({ max_claims: null, max_per_member: 1, period: "month", max_per_period: null, max_per_member_per_period: 1 });
    expect(input.rules.eligibility?.package_ids).toEqual([]);
    expect(input.rules).not.toHaveProperty("channel");
    expect(input.redemption).toEqual({ shared_code: "NUTRI10", link_url: null, low_pool_threshold: null, instructions: null });

    const link = toPerkInput(draft({ redemption_method: "partner_link", link_url: "https://shop.example/offer", benefit_type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1, item: "shaker", channel: "online" }));
    expect(link.redemption.shared_code).toBeNull();
    expect(link.redemption.link_url).toBe("https://shop.example/offer");
    expect(link.benefit).toEqual({ type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1, item: "shaker", text: null, min_spend_cents: null });
    expect(link.rules.channel).toBe("online");
  });

  it("reads a saved perk back into the form", () => {
    const perk = {
      partner_name: "Nutri",
      partner_url: null,
      partner_address: null,
      logo_media_id: null,
      redemption_method: "code_pool",
      benefit: { type: "fixed_amount", amount_cents: 500, currency: "EUR" },
      rules: {
        valid_from: "2026-11-01",
        valid_until: null,
        channel: "both",
        recurring: [{ weekdays: [6, 7], starts_at: "09:00:00", ends_at: "13:00:00" }],
        limits: { max_claims: 100, max_per_member: 2 },
        eligibility: { package_ids: ["pt"], min_tenure_days: 30 },
      },
      redemption: { low_pool_threshold: 5 },
      all_locations: true,
      location_ids: [],
      terms: null,
      valid_from: "2026-11-01",
      valid_until: null,
    } as unknown as StaffPerk;
    const back = draftFromPerk(perk);
    expect(back).toMatchObject({
      benefit_type: "fixed_amount",
      amount_cents: 500,
      channel: null,
      windows: [{ weekdays: [6, 7], from: "09:00", until: "13:00" }],
      max_claims: 100,
      max_per_member: 2,
      audience: "packages",
      package_ids: ["pt"],
      min_tenure_days: 30,
      low_pool_threshold: 5,
    });
  });
});

describe("partner code batches", () => {
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
