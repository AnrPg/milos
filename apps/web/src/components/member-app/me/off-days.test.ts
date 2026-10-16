import { describe, expect, it } from "vitest";

import { MAX_OFF_DAYS, toggleOffDay } from "@/components/member-app/me/off-days";

describe("toggleOffDay", () => {
  it("adds and removes a weekday, keeping the week order", () => {
    expect(toggleOffDay([3], 0)).toEqual([0, 3]);
    expect(toggleOffDay([0, 3], 3)).toEqual([0]);
  });

  it("allows as many rest days as the API does, and no more", () => {
    const full = [0, 1, 2, 3, 4];
    expect(full).toHaveLength(MAX_OFF_DAYS);
    expect(toggleOffDay([0, 1, 2, 3], 4)).toEqual(full);
    expect(toggleOffDay(full, 6)).toEqual(full);
  });
});
