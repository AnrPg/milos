import { describe, expect, it } from "vitest";

import type { StaffPerkInput } from "@/api/perks";

import { canPublishPerk, isPerkLive, localToday, normalizePerkCode, perkDaysLeft, perkDraftProblems, perkPhase } from "./validity";

const draft = (overrides: Partial<StaffPerkInput> = {}): StaffPerkInput => ({
  partner: { name: "Nutri Store Κυψέλη", category: "Συμπληρώματα", address: null, url: null, logo_media_id: null },
  offer: { kind: "percent", value: 10, text: "σε όλα τα συμπληρώματα", currency: "EUR" },
  terms: null,
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
});
