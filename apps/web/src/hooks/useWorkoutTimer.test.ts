import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { TimerSegment } from "@/api/executions";

import { useWorkoutTimer } from "./useWorkoutTimer";

function countdown(key: string, durationSeconds: number): TimerSegment {
  return {
    segment_key: key,
    section_id: "section-1",
    section_name: "Main",
    format: "tabata",
    kind: "countdown",
    duration_seconds: durationSeconds,
    round: 1,
    total_rounds: 8,
    label: key,
    exercises: [],
    scoreable: false,
    score_config: null,
    timer_config: {},
  } as unknown as TimerSegment;
}

type Props = {
  segment: TimerSegment;
  isActive: boolean;
  pausedElapsed: number;
  segmentStartedAt: number | null;
};

describe("useWorkoutTimer", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["Date", "setInterval", "clearInterval", "setTimeout", "clearTimeout"] });
    vi.setSystemTime(new Date("2026-10-12T10:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("counts down from the segment start", () => {
    const startedAt = Date.now();
    const { result } = renderHook(() => useWorkoutTimer(countdown("work", 20), true, 0, startedAt));

    act(() => {
      vi.advanceTimersByTime(5_020);
    });

    expect(result.current.elapsed).toBe(5);
    expect(result.current.remaining).toBe(15);
    expect(result.current.isExpired).toBe(false);
  });

  it("does not report a fresh segment as expired using the previous segment's elapsed time", () => {
    const work = countdown("work", 60);
    const rest = countdown("rest", 10);
    const { result, rerender } = renderHook(
      ({ segment, isActive, pausedElapsed, segmentStartedAt }: Props) =>
        useWorkoutTimer(segment, isActive, pausedElapsed, segmentStartedAt),
      { initialProps: { segment: work, isActive: true, pausedElapsed: 0, segmentStartedAt: Date.now() } },
    );

    act(() => {
      vi.advanceTimersByTime(25_020);
    });
    expect(result.current.elapsed).toBe(25);

    // Skip to the 10 s rest: the very first render must already be fresh, before any animation frame.
    rerender({ segment: rest, isActive: true, pausedElapsed: 0, segmentStartedAt: Date.now() });

    expect(result.current.elapsed).toBe(0);
    expect(result.current.remaining).toBe(10);
    expect(result.current.isExpired).toBe(false);
  });

  it("shows the frozen elapsed time while paused", () => {
    const { result } = renderHook(() => useWorkoutTimer(countdown("work", 60), false, 12_400, null));

    expect(result.current.elapsed).toBe(12);
    expect(result.current.remaining).toBe(48);
  });
});
