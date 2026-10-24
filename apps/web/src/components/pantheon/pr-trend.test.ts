import { describe, expect, it } from "vitest";

import { estimatedOneRepMax, prMatchesFilter, prTrend, trendLine } from "./pr-trend";

const squat = {
  id: "squat",
  unit: "kg" as const,
  higher_is_better: true,
  current_score: 130,
  beaten_on: "2026-10-01",
  supporting_metrics: { reps: 3 },
};

const history = [
  { pr_record_id: "squat", score: 120, beaten_on: "2026-05-01", supporting_metrics: { reps: 1 } },
  { pr_record_id: "squat", score: 125, beaten_on: "2026-08-15", supporting_metrics: {} },
  { pr_record_id: "other", score: 300, beaten_on: "2026-09-01", supporting_metrics: {} },
];

describe("estimated 1RM", () => {
  it("uses Epley, a single is the load, and refuses long sets", () => {
    expect(estimatedOneRepMax(100)).toBe(100);
    expect(estimatedOneRepMax(100, 3)).toBe(110);
    expect(estimatedOneRepMax(100, 5)).toBe(116.5);
    expect(estimatedOneRepMax(100, 13)).toBeNull();
    expect(estimatedOneRepMax(0, 1)).toBeNull();
  });
});

describe("PR trend", () => {
  it("draws a lift's estimated 1RM over the range from the last score before it", () => {
    const trend = prTrend(squat, history, { since: "2026-07-24", today: "2026-10-22" });
    expect(trend).toMatchObject({ kind: "strength", latest: 143, retestDue: false });
    expect(trend?.points).toEqual([
      { on: "2026-05-01", value: 120 },
      { on: "2026-08-15", value: 125 },
      { on: "2026-10-01", value: 143 },
    ]);
    expect(trend?.improvement).toBe(23);
  });

  it("covers all time without a range and ignores other PRs", () => {
    expect(prTrend(squat, history, { since: null, today: "2026-10-22" })?.points).toHaveLength(3);
  });

  it("hides a PR with nothing in the range and no hint", () => {
    expect(prTrend(squat, history, { since: "2026-10-10", today: "2026-10-22" })).toBeNull();
  });

  it("counts a faster benchmark as an improvement and hints a retest after 12 weeks", () => {
    const fran = {
      id: "fran",
      unit: "mins_secs" as const,
      higher_is_better: false,
      current_score: 252,
      beaten_on: "2026-06-01",
      supporting_metrics: {},
    };
    const franHistory = [{ pr_record_id: "fran", score: 270, beaten_on: "2026-03-01", supporting_metrics: {} }];
    const trend = prTrend(fran, franHistory, { since: null, today: "2026-10-22" });
    expect(trend).toMatchObject({ kind: "benchmark", latest: 252, improvement: 18, retestDue: true });
    // Out of range, the hint alone keeps the row.
    expect(prTrend(fran, franHistory, { since: "2026-09-01", today: "2026-10-22" })).toMatchObject({
      points: [{ on: "2026-06-01", value: 252 }],
      improvement: null,
      retestDue: true,
    });
    expect(prTrend(fran, franHistory, { since: null, today: "2026-07-01" })?.retestDue).toBe(false);
  });

  it("follows the source and exercise chips", () => {
    const gym = { name: "Back Squat", organization_id: "org-1" };
    const own = { name: "Τρέξιμο 5χλμ", organization_id: null };
    expect(prMatchesFilter(gym, { sources: [] })).toBe(true);
    expect(prMatchesFilter(gym, { sources: ["org-1"] })).toBe(true);
    expect(prMatchesFilter(own, { sources: ["org-1"] })).toBe(false);
    expect(prMatchesFilter(own, { sources: ["freeform"] })).toBe(true);
    expect(prMatchesFilter(gym, { sources: [], exercise: "squat" })).toBe(true);
    expect(prMatchesFilter(own, { sources: [], exercise: "τρεξιμο" })).toBe(true);
    expect(prMatchesFilter(gym, { sources: [], exercise: "deadlift" })).toBe(false);
  });

  it("draws better results higher, for times too", () => {
    expect(trendLine([{ on: "a", value: 270 }, { on: "b", value: 252 }], false, 60, 16)).toBe("0,16 60,0");
    expect(trendLine([{ on: "a", value: 100 }, { on: "b", value: 110 }], true, 60, 16)).toBe("0,16 60,0");
    expect(trendLine([{ on: "a", value: 100 }], true, 60, 16)).toBeNull();
  });
});
