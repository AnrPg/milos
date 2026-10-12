import { describe, expect, it } from "vitest";

import { hasStructuredContent, usesManualTimer } from "./workout-execution-mode";

const section = { exercises: [{ item_type: "exercise" }] };

describe("usesManualTimer", () => {
  it("runs structured and quick-text workouts on their timers", () => {
    expect(usesManualTimer({ authoring_mode: "structured", sections: [] })).toBe(false);
    expect(usesManualTimer(null)).toBe(false);
  });

  it("runs parsed free-text workouts on their timers", () => {
    expect(usesManualTimer({ authoring_mode: "free_text", sections: [section], workout_metadata: { timer_inference: "complete" } })).toBe(false);
    expect(usesManualTimer({ authoring_mode: "free_text", sections: [section] })).toBe(false);
  });

  it("falls back to the manual timer without structure or with uninferred timers", () => {
    expect(usesManualTimer({ authoring_mode: "free_text", sections: [] })).toBe(true);
    expect(usesManualTimer({ authoring_mode: "free_text" })).toBe(true);
    expect(usesManualTimer({ authoring_mode: "free_text", sections: [{ exercises: [{ item_type: "header" }] }] })).toBe(true);
    expect(usesManualTimer({ authoring_mode: "free_text", sections: [section], workout_metadata: { timer_inference: "incomplete" } })).toBe(true);
  });

  it("finds exercises in nested sections", () => {
    expect(hasStructuredContent([{ exercises: [], sections: [section] }])).toBe(true);
  });
});
