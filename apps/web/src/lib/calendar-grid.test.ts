import { describe, expect, it } from "vitest";

import { addMonths, isoDay, monthGrid, parseIsoDay, parseTime, weekday, withinRange } from "./calendar-grid";

describe("calendar grid", () => {
  it("parses and prints ISO days, rejecting impossible dates", () => {
    expect(parseIsoDay("2026-10-22")).toEqual({ year: 2026, month: 10, day: 22 });
    expect(parseIsoDay("2026-02-30")).toBeNull();
    expect(parseIsoDay("")).toBeNull();
    expect(isoDay({ year: 2026, month: 3, day: 7 })).toBe("2026-03-07");
  });

  it("builds six whole weeks starting on the locale's first weekday", () => {
    const monday = monthGrid(2026, 10, 1);
    expect(monday).toHaveLength(42);
    expect(weekday(monday[0])).toBe(1);
    expect(isoDay(monday[0])).toBe("2026-09-28");
    const sunday = monthGrid(2026, 10, 0);
    expect(weekday(sunday[0])).toBe(0);
    expect(isoDay(sunday[0])).toBe("2026-09-27");
  });

  it("clamps month moves to the target month's length", () => {
    expect(isoDay(addMonths({ year: 2026, month: 1, day: 31 }, 1))).toBe("2026-02-28");
    expect(isoDay(addMonths({ year: 2026, month: 1, day: 15 }, -1))).toBe("2025-12-15");
  });

  it("checks min and max and reads times", () => {
    const day = { year: 2026, month: 10, day: 22 };
    expect(withinRange(day, parseIsoDay("2026-10-22"), null)).toBe(true);
    expect(withinRange(day, parseIsoDay("2026-10-23"), null)).toBe(false);
    expect(parseTime("18:05")).toEqual({ hour: 18, minute: 5 });
    expect(parseTime("25:00")).toBeNull();
  });
});
