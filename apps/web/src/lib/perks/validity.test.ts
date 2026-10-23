import { describe, expect, it } from "vitest";

import type { StaffPerkInput } from "@/api/perks";

import {
  MAX_CODES_PER_UPLOAD,
  canPublishPerk,
  codesLeft,
  isPerkLive,
  localToday,
  normalizePerkCode,
  parsePerkCodes,
  perkDaysLeft,
  perkDraftProblems,
  perkPhase,
} from "./validity";

const draft = (overrides: Partial<StaffPerkInput> = {}): StaffPerkInput => ({
  partner: { name: "Nutri Store Κυψέλη", category: "Συμπληρώματα", address: null, url: null, logo_media_id: null },
  offer: { kind: "percent", value: 10, text: "σε όλα τα συμπληρώματα", currency: "EUR" },
  terms: null,
  redemption: "partner_codes",
  code_mode: "shared",
  shared_code: "ΚΥΨΕΛΗ10",
  show_qr: true,
  starts_on: "2026-10-23",
  ends_on: "2026-12-31",
  audience: "all_members",
  package_ids: [],
  all_locations: true,
  location_ids: [],
  per_member_limit: null,
  total_limit: null,
  box_benefits: true,
  announce: false,
  status: "draft",
  ...overrides,
});

describe("perk validity", () => {
  it("places a perk on the day", () => {
    const perk = { status: "active" as const, starts_on: "2026-11-01", ends_on: "2026-12-31" };
    expect(perkPhase(perk, "2026-10-23")).toBe("scheduled");
    expect(perkPhase(perk, "2026-11-01")).toBe("active");
    expect(perkPhase(perk, "2026-12-31")).toBe("active");
    expect(perkPhase(perk, "2027-01-01")).toBe("expired");
    expect(perkPhase({ ...perk, status: "paused" }, "2026-11-10")).toBe("paused");
    expect(perkPhase({ ...perk, status: "draft" }, "2026-11-10")).toBe("draft");
    expect(perkPhase({ status: "active", starts_on: null, ends_on: null }, "2030-01-01")).toBe("active");
  });

  it("shows a member only what is live today", () => {
    expect(isPerkLive({ starts_on: null, ends_on: "2026-10-22" }, "2026-10-23")).toBe(false);
    expect(isPerkLive({ starts_on: "2026-10-23", ends_on: null }, "2026-10-23")).toBe(true);
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
          partner: { name: " ", category: null, address: null, url: null, logo_media_id: null },
          offer: { kind: "percent", value: 120, text: "", currency: "EUR" },
          shared_code: "a",
          ends_on: "2026-10-01",
          audience: "packages",
          all_locations: false,
          per_member_limit: 0,
        }),
      ),
    ).toEqual(["partnerName", "offerText", "percent", "code", "dates", "packages", "branches", "perMemberLimit"]);
    expect(perkDraftProblems(draft({ offer: { kind: "amount", value: 0, text: "x", currency: "EUR" } }))).toEqual(["amount"]);
    expect(perkDraftProblems(draft({ offer: { kind: "gift", value: null, text: "shot", currency: "EUR" } }))).toEqual([]);
  });

  it("normalises a typed code to the shape members see", () => {
    expect(normalizePerkCode(" κυψέλη 10 ")).toBe("ΚΥΨΕΛΗ10");
    expect(perkDraftProblems(draft({ shared_code: " palee-10 " }))).toEqual([]);
  });

  it("lets a demo business draft but not publish", () => {
    expect(canPublishPerk(draft(), "demo")).toBe(false);
    expect(canPublishPerk(draft(), "active")).toBe(true);
    expect(canPublishPerk(draft({ shared_code: "" }), "active")).toBe(false);
  });

  it("needs unique codes before a perk of unique codes goes live", () => {
    const unique = draft({ code_mode: "unique", shared_code: null });
    expect(perkDraftProblems(unique)).toEqual([]);
    expect(canPublishPerk(unique, "active", 0)).toBe(false);
    expect(canPublishPerk(unique, "active", 12)).toBe(true);
  });

  it("needs no code for a Palee QR", () => {
    const qr = draft({ redemption: "palee_qr", shared_code: null, code_mode: "unique" });
    expect(perkDraftProblems(qr)).toEqual([]);
    expect(canPublishPerk(qr, "active", 0)).toBe(true);
  });
});

describe("unique code batches", () => {
  it("reads pasted lines and CSV cells, skipping a header and repeats", () => {
    expect(parsePerkCodes("code\nNS-001\nns-002, NS-003;NS-001\n\n\"NS-004\"\tx\n")).toEqual({
      codes: ["NS-001", "NS-002", "NS-003", "NS-004"],
      duplicates: 1,
      invalid: 1,
      tooMany: false,
    });
  });

  it("caps one upload", () => {
    const text = Array.from({ length: MAX_CODES_PER_UPLOAD + 2 }, (_, index) => `C${index}AA`).join("\n");
    const parsed = parsePerkCodes(text);
    expect(parsed.codes).toHaveLength(MAX_CODES_PER_UPLOAD);
    expect(parsed.tooMany).toBe(true);
  });

  it("counts what is left to hand out", () => {
    expect(codesLeft({ codes_total: 50, codes_claimed: 12 })).toBe(38);
    expect(codesLeft({ codes_total: 5, codes_claimed: 9 })).toBe(0);
  });
});
