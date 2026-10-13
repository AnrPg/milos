import { describe, expect, it } from "vitest";

import { defaultHistoryKind, exerciseText } from "./training-history";

describe("training log helpers", () => {
  it("opens members on classes and athletes on workouts", () => {
    expect(defaultHistoryKind("member")).toBe("classes");
    expect(defaultHistoryKind("athlete")).toBe("workouts");
  });

  it("summarises an exercise prescription", () => {
    expect(exerciseText({ name: "Back Squat", sets: 5, prescription_value: 5, prescription_unit: "reps", load_value: 100, load_mode: "absolute" })).toBe("5×5 Back Squat @ 100 kg");
    expect(exerciseText({ name: "Row", prescription_value: 500, prescription_unit: "meters" })).toBe("500 meters Row");
    expect(exerciseText({ name: "Thruster", load_value: 70, load_mode: "pct_1rm" })).toBe("Thruster @ 70%");
  });
});
