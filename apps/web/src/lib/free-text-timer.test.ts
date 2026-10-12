import { describe, expect, it } from "vitest";

import fixtures from "./timer-preset-fixtures.json";
import { buildFreeTextSegments, freeTextPosition, parseFreeTextTimerPreset, runElapsedMs } from "./free-text-timer";

describe("free-text timer", () => {
  it("runs a Tabata as work/rest intervals without a trailing rest", () => {
    const segments = buildFreeTextSegments({ format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 2 });
    expect(segments.map((segment) => [segment.phase, segment.duration_seconds])).toEqual([
      ["work", 20],
      ["rest", 10],
      ["work", 20],
    ]);

    const inRest = freeTextPosition(segments, 25_000);
    expect(inRest.index).toBe(1);
    expect(inRest.clock.remainingMs).toBe(5_000);
    expect(inRest.finished).toBe(false);

    const done = freeTextPosition(segments, 99_000);
    expect(done.finished).toBe(true);
    expect(done.totalElapsedMs).toBe(50_000);
  });

  it("counts EMOM windows on one interval cycle", () => {
    const [emom] = buildFreeTextSegments({ format: "emom", interval_seconds: 60, rounds: 10 });
    const position = freeTextPosition([emom!], 125_000);
    expect(position.clock.window).toMatchObject({ index: 3, count: 10 });
    expect(position.clock.remainingMs).toBe(55_000);
  });

  it("keeps a stopwatch running without an end", () => {
    const position = freeTextPosition(buildFreeTextSegments({ format: "untimed" }), 3_600_000);
    expect(position.finished).toBe(false);
    expect(position.clock.elapsedMs).toBe(3_600_000);
  });

  it("derives elapsed time from wall-clock timestamps", () => {
    expect(runElapsedMs({ startedAt: 1_000, carriedMs: 5_000 }, 4_000)).toBe(8_000);
    expect(runElapsedMs({ startedAt: null, carriedMs: 5_000 }, 4_000)).toBe(5_000);
  });

  it("rejects malformed presets from metadata", () => {
    expect(parseFreeTextTimerPreset({ format: "bogus" })).toBeNull();
    expect(parseFreeTextTimerPreset({ format: "amrap", duration_seconds: -5 })).toMatchObject({
      format: "amrap",
      duration_seconds: null,
    });
  });
});

describe("timer preset parity with the API", () => {
  it.each(fixtures.cases.map((entry) => [entry.preset.format, entry] as const))("builds %s like the server", (_format, entry) => {
    const segments = buildFreeTextSegments(parseFreeTextTimerPreset(entry.preset)!);
    expect(segments.map((segment) => [segment.kind, segment.phase, segment.duration_seconds, segment.total_rounds])).toEqual(
      entry.segments,
    );
  });
});
