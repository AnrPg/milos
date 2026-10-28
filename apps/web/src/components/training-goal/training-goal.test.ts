import { describe, expect, it } from "vitest";

import { goalBounds, goalSetterNote, stepGoal, weeklyTarget } from "@/components/training-goal/training-goal";

describe("training goal helpers (ADR-216)", () => {
  it("keeps steps inside the bounds the API accepts", () => {
    expect(stepGoal(2, 1)).toBe(3);
    expect(stepGoal(1, -1)).toBe(1);
    expect(stepGoal(14, 1)).toBe(14);
    expect(stepGoal(5, 1, goalBounds({ min: 1, max: 5 }))).toBe(5);
  });

  it("falls back to the default target without a goal", () => {
    expect(weeklyTarget(null)).toBe(2);
    expect(weeklyTarget({ weekly_workout_target: 4 })).toBe(4);
  });

  it("says who set the goal", () => {
    expect(goalSetterNote(null)).toEqual({ kind: "default" });
    expect(goalSetterNote({ weekly_workout_target: 2, is_default: true, set_by_role: null })).toEqual({ kind: "default" });
    expect(goalSetterNote({ weekly_workout_target: 3, is_default: false, set_by_role: "self" })).toEqual({ kind: "self" });
    expect(
      goalSetterNote({ weekly_workout_target: 5, is_default: false, set_by_role: "coach", set_by_nickname: "Nikos" }),
    ).toEqual({ kind: "coach", name: "Nikos" });
  });
});
