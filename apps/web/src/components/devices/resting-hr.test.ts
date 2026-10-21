import { describe, expect, it } from "vitest";

import type { DailyStats } from "@/api/devices";

import { dailyValues, restingHrView, sparkline } from "./resting-hr";

const stats = (points: DailyStats["points"], overrides: Partial<DailyStats> = {}): DailyStats => ({
  metric: "resting_hr",
  range: "3m",
  from: "2026-07-24",
  to: "2026-10-21",
  points,
  latest: points[points.length - 1] ?? null,
  average: null,
  sources: [...new Set(points.map((point) => point.source))],
  ...overrides,
});

describe("resting heart rate", () => {
  it("shows no card without data", () => {
    expect(restingHrView(null)).toBeNull();
    expect(restingHrView(stats([]))).toBeNull();
    expect(restingHrView({} as DailyStats)).toBeNull();
  });

  it("averages two devices on the same day and keeps days in order", () => {
    expect(
      dailyValues([
        { on: "2026-10-20", value: 50, source: "garmin" },
        { on: "2026-10-19", value: 53, source: "garmin" },
        { on: "2026-10-20", value: 52, source: "apple_health" },
      ]),
    ).toEqual([
      { on: "2026-10-19", value: 53 },
      { on: "2026-10-20", value: 51 },
    ]);
  });

  it("reads the latest reading, the server's average and the range", () => {
    const view = restingHrView(
      stats(
        [
          { on: "2026-10-19", value: 55, source: "garmin" },
          { on: "2026-10-20", value: 52, source: "garmin" },
          { on: "2026-10-21", value: 49, source: "garmin" },
        ],
        { average: 52 },
      ),
    );
    expect(view).toMatchObject({ latest: { value: 49, source: "garmin" }, average: 52, days: 3, low: 49, high: 55, sources: ["garmin"] });
    expect(view?.line).toBe("0,0 120,24 240,48");
  });

  it("computes the average when the server leaves it out and draws no line for one day", () => {
    const view = restingHrView(stats([{ on: "2026-10-21", value: 50, source: "garmin" }]));
    expect(view).toMatchObject({ average: 50, days: 1 });
    expect(view?.line).toBeNull();
  });

  it("draws a flat line in the middle when every day is the same", () => {
    expect(sparkline([50, 50, 50], 100, 20)).toBe("0,10 50,10 100,10");
  });
});
