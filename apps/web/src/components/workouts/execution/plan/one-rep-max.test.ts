import { describe, expect, it } from "vitest";

import { normalizeExerciseName, oneRepMaxLookup } from "./one-rep-max";

describe("oneRepMaxLookup", () => {
  it("reads 1RMs in kg from PRs, matching names loosely, and ignores other PRs", () => {
    const lookup = oneRepMaxLookup([
      { name: "Back Squat 1RM", unit: "kg", current_score: 140, supporting_metrics: {} },
      { name: "back squat", unit: "kg", current_score: 150, supporting_metrics: { reps: 1 } },
      { name: "Front Squat", unit: "kg", current_score: 120, supporting_metrics: { reps: 3 } },
      { name: "Fran", unit: "mins_secs", current_score: 200, supporting_metrics: {} },
      { name: "Πρέσσα 1RM", unit: "kg", current_score: 60, supporting_metrics: {} },
    ]);
    expect(lookup("Back Squat", null)).toBe(150);
    expect(lookup("Front Squat", null)).toBeNull();
    expect(lookup("πρεσσα", null)).toBe(60);
    expect(lookup("Deadlift", null)).toBeNull();
    expect(normalizeExerciseName("Clean & Jerk 1RM")).toBe("clean jerk");
  });
});
