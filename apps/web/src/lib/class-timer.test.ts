import { describe, expect, it } from "vitest";

import type { ClassTimerState } from "@/api/class-timers";

import { classTimerPosition, clockOffsetMs } from "./class-timer";
import { buildFreeTextSegments } from "./free-text-timer";

const segments = buildFreeTextSegments({ format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 2 });
const t0 = Date.parse("2026-10-12T18:00:00.000Z");

function state(overrides: Partial<ClassTimerState>): ClassTimerState {
  return {
    status: "running",
    current_segment_index: 0,
    segment_started_at_utc: new Date(t0).toISOString(),
    paused_elapsed_ms: 0,
    duration_adjustments: {},
    timer_preset: null,
    lock_version: 2,
    ...overrides,
  };
}

describe("classTimerPosition", () => {
  it("counts down to a start in the future (get ready)", () => {
    const position = classTimerPosition(segments, state({}), t0 - 4_000);
    expect(position.startsInMs).toBe(4_000);
    expect(position.index).toBe(0);
  });

  it("catches up through ended segments exactly like the server", () => {
    const position = classTimerPosition(segments, state({}), t0 + 35_000);
    expect(position.index).toBe(2);
    expect(position.clock?.elapsedMs).toBe(5_000);
    expect(position.status).toBe("running");
  });

  it("finishes when the last segment runs out", () => {
    const position = classTimerPosition(segments, state({}), t0 + 120_000);
    expect(position.status).toBe("finished");
    expect(position.clock?.remainingMs).toBe(0);
  });

  it("shows banked time while paused", () => {
    const position = classTimerPosition(
      segments,
      state({ status: "paused", segment_started_at_utc: null, paused_elapsed_ms: 8_000 }),
      t0 + 999_000,
    );
    expect(position.clock?.remainingMs).toBe(12_000);
  });
});

describe("clockOffsetMs", () => {
  it("assumes the server stamped the response halfway through the round trip", () => {
    expect(clockOffsetMs(new Date(t0 + 5_000).toISOString(), t0, t0 + 200)).toBe(4_900);
  });
});
