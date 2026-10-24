import { describe, expect, it } from "vitest";

import {
  dailyStatsRange,
  numericScore,
  rangeSince,
  scaleWeekly,
  sourceShares,
  sparklinePoints,
} from "@/components/client/progress";

describe("the one Πρόοδος range", () => {
  it("starts each range where the API does, months clamped to their last day", () => {
    expect(rangeSince("all", "2026-10-22")).toBeNull();
    expect(rangeSince("4w", "2026-10-22")).toBe("2026-09-24");
    expect(rangeSince("12w", "2026-10-22")).toBe("2026-07-30");
    expect(rangeSince("6m", "2026-08-31")).toBe("2026-02-28");
    expect(rangeSince("1y", "2028-02-29")).toBe("2027-02-28");
    expect(rangeSince("6m", "2026-03-15")).toBe("2025-09-15");
  });

  it("maps the range to the device series that covers it", () => {
    expect(dailyStatsRange("4w")).toBe("1m");
    expect(dailyStatsRange("6m")).toBe("6m");
    expect(dailyStatsRange("all")).toBe("1y");
  });
});

describe("progress chart helpers", () => {
  const weekly = [
    { week_start: "2026-10-05", sessions: 2, minutes: 90 },
    { week_start: "2026-09-28", sessions: 4, minutes: 180 },
    { week_start: "2026-09-21", sessions: 0, minutes: 0 },
  ];

  it("orders weeks oldest first and scales them to the busiest week", () => {
    expect(scaleWeekly(weekly, "sessions")).toEqual([
      { week_start: "2026-09-21", value: 0, percent: 0 },
      { week_start: "2026-09-28", value: 4, percent: 100 },
      { week_start: "2026-10-05", value: 2, percent: 50 },
    ]);
    expect(scaleWeekly(weekly, "minutes", 2).map((bar) => bar.percent)).toEqual([100, 50]);
  });

  it("keeps empty history flat instead of dividing by zero", () => {
    expect(scaleWeekly([{ week_start: "2026-10-05", sessions: 0, minutes: 0 }], "minutes")).toEqual([
      { week_start: "2026-10-05", value: 0, percent: 0 },
    ]);
    expect(scaleWeekly([], "sessions")).toEqual([]);
  });

  it("reads numbers, numeric strings and clock times as chartable scores", () => {
    expect(numericScore(42)).toBe(42);
    expect(numericScore(" 102.5 ")).toBe(102.5);
    expect(numericScore("4:05")).toBe(245);
    expect(numericScore("1:02:03")).toBe(3723);
    expect(numericScore("5 rounds + 3 reps")).toBeNull();
  });

  it("draws a sparkline only with two or more numeric points", () => {
    const point = (value: number | string) => ({ completed_on: "2026-10-01", execution_id: "e", value });
    expect(sparklinePoints({ points: [point(10), point("n/a")] }, 100, 20)).toBeNull();
    expect(sparklinePoints({ points: [point(10), point(20), point(15)] }, 100, 20)).toBe("0,20 50,0 100,10");
    expect(sparklinePoints({ points: [point(5), point(5)] }, 60, 20)).toBe("0,10 60,10");
  });

  it("breaks sessions down by source, largest first", () => {
    expect(sourceShares({ assigned: 1, class_booking: 3, repeat: 0 })).toEqual([
      { source: "class_booking", count: 3, percent: 75 },
      { source: "assigned", count: 1, percent: 25 },
    ]);
  });
});
