import { describe, expect, it } from "vitest";

import { activities, dailies, localDay, nights, toIngestBatches, weights, withOffset } from "./health-batch";

describe("withOffset", () => {
  it("writes the wearer's local time with the offset", () => {
    expect(withOffset("2026-10-20T04:30:00.000Z", 180)).toBe("2026-10-20T07:30:00+03:00");
    expect(withOffset("2026-10-20T01:00:00Z", -330)).toBe("2026-10-19T19:30:00-05:30");
    expect(withOffset("2026-10-20T01:00:00Z", -30)).toBe("2026-10-20T00:30:00-00:30");
    expect(withOffset("2026-10-20T01:00:00Z", null)).toBe("2026-10-20T01:00:00+00:00");
    expect(withOffset("not a date", 0)).toBeNull();
  });

  it("gives the local day", () => {
    expect(localDay("2026-10-19T22:30:00Z", 120)).toBe("2026-10-20");
  });
});

describe("activities", () => {
  it("keeps the numbers that are there and drops broken rows", () => {
    expect(
      activities([
        { id: "a", type: "RUNNING", start: "2026-10-20T05:00:00Z", end: "2026-10-20T05:40:00Z", offset_minutes: 180, distance_m: 7000, avg_hr: null, source_app: "Watch" },
        { id: "", start: "2026-10-20T05:00:00Z", end: "2026-10-20T05:40:00Z" },
        { id: "b", start: "nope", end: "2026-10-20T05:40:00Z" },
      ]),
    ).toEqual([
      { id: "a", type: "RUNNING", start: "2026-10-20T08:00:00+03:00", end: "2026-10-20T08:40:00+03:00", distance_m: 7000, source_app: "Watch" },
    ]);
  });
});

describe("nights", () => {
  it("joins a night's segments across a short wake-up, keyed by the day it ends", () => {
    expect(
      nights([
        { id: "1", start: "2026-10-19T20:40:00Z", end: "2026-10-20T00:10:00Z", offset_minutes: 180, stage: "asleep" },
        { id: "2", start: "2026-10-20T00:10:00Z", end: "2026-10-20T00:25:00Z", offset_minutes: 180, stage: "awake" },
        { id: "3", start: "2026-10-20T00:25:00Z", end: "2026-10-20T03:50:00Z", offset_minutes: 180, stage: "asleep" },
        { id: "bed", start: "2026-10-19T20:20:00Z", end: "2026-10-20T04:00:00Z", offset_minutes: 180, stage: "in_bed" },
      ]),
    ).toEqual([{ id: "2026-10-20", start: "2026-10-19T23:40:00+03:00", end: "2026-10-20T06:50:00+03:00" }]);
  });

  it("keeps the longest sleep of a day and skips dozes", () => {
    expect(
      nights([
        { id: "n", start: "2026-10-19T22:00:00Z", end: "2026-10-20T06:00:00Z", stage: "session" },
        { id: "nap", start: "2026-10-20T13:00:00Z", end: "2026-10-20T14:00:00Z", stage: "session" },
        { id: "doze", start: "2026-10-21T15:00:00Z", end: "2026-10-21T15:20:00Z", stage: "session" },
      ]),
    ).toEqual([{ id: "2026-10-20", start: "2026-10-19T22:00:00+00:00", end: "2026-10-20T06:00:00+00:00" }]);
  });

  it("uses time in bed only for nights without sleep data", () => {
    expect(nights([{ id: "bed", start: "2026-10-19T22:00:00Z", end: "2026-10-20T05:30:00Z", stage: "in_bed" }])).toEqual([
      { id: "2026-10-20", start: "2026-10-19T22:00:00+00:00", end: "2026-10-20T05:30:00+00:00" },
    ]);
  });
});

describe("weights and dailies", () => {
  it("rounds kilograms and joins a day's numbers", () => {
    expect(weights([{ id: "w", at: "2026-10-20T05:00:00Z", offset_minutes: 120, kg: 71.8449 }])).toEqual([
      { id: "w", at: "2026-10-20T07:00:00+02:00", kg: 71.84 },
    ]);
    expect(
      dailies({
        resting_hr: [{ date: "2026-10-20", bpm: 51.6 }],
        steps: [
          { date: "2026-10-21", count: 2300.4 },
          { date: "2026-10-20", count: 9120 },
          { date: "bad", count: 1 },
        ],
      }),
    ).toEqual([
      { date: "2026-10-20", resting_hr: 52, steps: 9120 },
      { date: "2026-10-21", steps: 2300 },
    ]);
  });
});

describe("toIngestBatches", () => {
  it("cuts long lists into batches of at most the limit", () => {
    const steps = Array.from({ length: 5 }, (_, index) => ({ date: `2026-10-0${index + 1}`, count: index }));
    const batches = toIngestBatches(
      { steps, workouts: [{ id: "a", start: "2026-10-01T05:00:00Z", end: "2026-10-01T06:00:00Z" }] },
      2,
    );
    expect(batches).toHaveLength(3);
    expect(batches[0].dailies).toHaveLength(2);
    expect(batches[0].activities).toHaveLength(1);
    expect(batches[2]).toEqual({ dailies: [{ date: "2026-10-05", steps: 4 }] });
  });

  it("has no batch for an empty read", () => {
    expect(toIngestBatches({})).toEqual([]);
  });
});
