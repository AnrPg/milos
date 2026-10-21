import { describe, expect, it } from "vitest";

import { todayItemHref } from "@/components/providers/TodayAcrossCard";

describe("«Σήμερα» across providers", () => {
  it("opens each kind where Box keeps it", () => {
    expect(todayItemHref({ kind: "class", id: "slot 1" })).toBe("/box/schedule?open_slot=slot%201");
    expect(todayItemHref({ kind: "appointment", id: "a" })).toBe("/box/appointments");
    expect(todayItemHref({ kind: "program", id: "as-1" })).toBe("/box/workouts?open_assignment=as-1");
    expect(todayItemHref({ kind: "wod", id: "w" })).toBe("/box");
  });
});
