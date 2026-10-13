import { describe, expect, it } from "vitest";

import { type CueSnapshot, nextCue } from "./timer-cues";

const snapshot = (overrides: Partial<CueSnapshot> = {}): CueSnapshot => ({
  segmentKey: "segment:0",
  running: true,
  remaining: 20,
  phase: "work",
  ...overrides,
});

describe("nextCue", () => {
  it("announces the phase when a segment starts", () => {
    expect(nextCue(null, snapshot())).toBe("work");
    expect(nextCue(snapshot(), snapshot({ segmentKey: "segment:1", phase: "rest" }))).toBe("rest");
  });

  it("announces the phase again when the timer resumes", () => {
    expect(nextCue(snapshot({ running: false }), snapshot())).toBe("work");
  });

  it("ticks once per second for the last three seconds", () => {
    expect(nextCue(snapshot({ remaining: 4 }), snapshot({ remaining: 3 }))).toBe("tick");
    expect(nextCue(snapshot({ remaining: 3 }), snapshot({ remaining: 3 }))).toBeNull();
    expect(nextCue(snapshot({ remaining: 2 }), snapshot({ remaining: 1 }))).toBe("tick");
  });

  it("stays quiet mid-segment, while paused and for untimed segments", () => {
    expect(nextCue(snapshot({ remaining: 12 }), snapshot({ remaining: 11 }))).toBeNull();
    expect(nextCue(snapshot(), snapshot({ running: false, remaining: 2 }))).toBeNull();
    expect(nextCue(snapshot({ remaining: null }), snapshot({ remaining: null }))).toBeNull();
  });
});
