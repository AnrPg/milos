import { describe, expect, it } from "vitest";

import type { MembershipFreeze } from "@/api/admin-users";
import {
  freezeDays,
  freezeDaysPerYear,
  freezeDaysUsedInYear,
  freezeState,
} from "@/components/admin/users/membership-freezes";

function freeze(starts_on: string, ends_on: string, cancelled_at: string | null = null): MembershipFreeze {
  return { id: `${starts_on}-${ends_on}`, starts_on, ends_on, extension_days: 0, reason: "travel", cancelled_at };
}

describe("freezeDays", () => {
  it("counts both ends of the range, like the API", () => {
    expect(freezeDays("2026-03-01", "2026-03-01")).toBe(1);
    expect(freezeDays("2026-03-01", "2026-03-14")).toBe(14);
    expect(freezeDays("2026-02-27", "2026-03-02")).toBe(4);
  });

  it("returns 0 for reversed or incomplete ranges", () => {
    expect(freezeDays("2026-03-10", "2026-03-01")).toBe(0);
    expect(freezeDays("2026-03-10", "")).toBe(0);
  });
});

describe("freezeDaysUsedInYear", () => {
  it("ignores cancelled freezes and clips ranges to the year", () => {
    const freezes = [
      freeze("2026-03-01", "2026-03-10"),
      freeze("2026-05-01", "2026-05-20", "2026-04-30T10:00:00Z"),
      freeze("2026-12-28", "2027-01-05"),
    ];
    expect(freezeDaysUsedInYear(freezes, 2026)).toBe(10 + 4);
    expect(freezeDaysUsedInYear(freezes, 2027)).toBe(5);
  });
});

describe("freezeDaysPerYear", () => {
  it("reads the active package's yearly freeze days", () => {
    expect(
      freezeDaysPerYear([
        { status: "expired", fields: { "perks.freeze_days_per_year": 60 } },
        { status: "active", fields: { "perks.freeze_days_per_year": 30 } },
      ]),
    ).toBe(30);
    expect(freezeDaysPerYear([{ status: "active", fields: {} }])).toBe(0);
    expect(freezeDaysPerYear([])).toBe(0);
  });
});

describe("freezeState", () => {
  it("places a freeze relative to today", () => {
    expect(freezeState(freeze("2026-03-01", "2026-03-10"), "2026-02-28")).toBe("upcoming");
    expect(freezeState(freeze("2026-03-01", "2026-03-10"), "2026-03-10")).toBe("active");
    expect(freezeState(freeze("2026-03-01", "2026-03-10"), "2026-03-11")).toBe("ended");
    expect(freezeState(freeze("2026-03-01", "2026-03-10", "2026-03-02T00:00:00Z"), "2026-03-05")).toBe("cancelled");
  });
});
