import { describe, expect, it } from "vitest";

import type { TimerSegment } from "@/api/executions";

import { intervalWindowAt, liveElapsedMs, planCatchUp, readSegmentClock, segmentLimitMs } from "./timer-engine";

function seg(overrides: Partial<TimerSegment>): TimerSegment {
  return {
    segment_key: "segment:0",
    section_id: "s",
    section_name: "S",
    format: "tabata",
    kind: "countdown",
    duration_seconds: 20,
    round: null,
    total_rounds: null,
    label: "Work",
    scoreable: false,
    score_config: null,
    timer_config: {},
    exercises: [],
    ...overrides,
  } as TimerSegment;
}

describe("segment clock", () => {
  it("counts a countdown down and expires at its duration", () => {
    const work = seg({ duration_seconds: 20 });
    expect(readSegmentClock(work, 5_000)).toMatchObject({ remainingMs: 15_000, isExpired: false, progress: 0.25 });
    expect(readSegmentClock(work, 20_000)).toMatchObject({ remainingMs: 0, isExpired: true });
  });

  it("runs an uncapped count-up forever", () => {
    expect(readSegmentClock(seg({ kind: "countup", duration_seconds: null }), 3_600_000)).toMatchObject({
      remainingMs: null,
      isExpired: false,
      limitMs: null,
    });
  });

  it("tracks the window of an open-ended interval cycle", () => {
    const deathBy = seg({ kind: "interval_cycle", duration_seconds: 60, total_rounds: null });
    expect(readSegmentClock(deathBy, 125_000)).toMatchObject({
      isExpired: false,
      remainingMs: 55_000,
      window: { index: 3, count: null, elapsedMs: 5_000, lengthMs: 60_000 },
    });
    expect(segmentLimitMs(deathBy)).toBeNull();
  });

  it("caps an interval cycle and cycles an authored window pattern", () => {
    const emom = seg({
      kind: "interval_cycle",
      duration_seconds: 60,
      total_rounds: 3,
      timer_config: { interval_pattern_seconds: [60, 120] },
    });
    expect(segmentLimitMs(emom)).toBe(240_000);
    expect(intervalWindowAt(emom, 61_000)).toMatchObject({ index: 2, elapsedMs: 1_000, lengthMs: 120_000 });
    expect(intervalWindowAt(emom, 185_000)).toMatchObject({ index: 3, elapsedMs: 5_000, lengthMs: 60_000 });
    expect(readSegmentClock(emom, 240_000).isExpired).toBe(true);
  });
});

describe("liveElapsedMs", () => {
  it("adds the running stretch to banked pause time", () => {
    expect(liveElapsedMs({ pausedElapsed: 4_000, segmentStartedAt: 10_000, running: true, now: 13_500 })).toBe(7_500);
    expect(liveElapsedMs({ pausedElapsed: 4_000, segmentStartedAt: 10_000, running: false, now: 13_500 })).toBe(4_000);
  });
});

describe("planCatchUp", () => {
  const tabata = [
    seg({ segment_key: "segment:0", duration_seconds: 20 }),
    seg({ segment_key: "segment:1", duration_seconds: 10 }),
    seg({ segment_key: "segment:2", duration_seconds: 20 }),
    seg({ segment_key: "segment:3", duration_seconds: 10 }),
    seg({ segment_key: "segment:4", duration_seconds: 20 }),
  ];

  it("starts the next segment exactly when the previous one ended", () => {
    // Expiry noticed 300 ms late (a slow tick or network round-trip).
    const plan = planCatchUp(tabata, 0, 0, 20_300, () => true);
    expect(plan).toEqual({ completed: [{ index: 0, elapsedMs: 20_000 }], index: 1, segmentStartedAt: 20_000 });
  });

  it("fast-forwards through everything that ran out while the phone was locked", () => {
    const plan = planCatchUp(tabata, 0, 0, 65_000, () => true);
    expect(plan.completed.map((step) => step.index)).toEqual([0, 1, 2, 3]);
    expect(plan.index).toBe(4);
    expect(plan.segmentStartedAt).toBe(60_000);
  });

  it("stops at a segment that must be handled by the athlete", () => {
    const plan = planCatchUp(tabata, 0, 0, 65_000, (index) => index !== 2);
    expect(plan.index).toBe(2);
    expect(plan.segmentStartedAt).toBe(30_000);
  });

  it("never advances past the last segment", () => {
    const plan = planCatchUp(tabata, 4, 0, 999_000, () => true);
    expect(plan).toEqual({ completed: [], index: 4, segmentStartedAt: 0 });
  });
});
