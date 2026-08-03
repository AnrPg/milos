import { describe, expect, it } from "vitest";

import { isSectionComplete } from "@/stores/workout-creation";

import {
  concreteSetPrescriptions,
  makeDefaultExercise,
  makeDefaultHeader,
  makeDefaultSection,
} from "./workout";

describe("structured workout sets", () => {
  it("preserves per-set reps while a percentage deload controls set loads", () => {
    const exercise = {
      ...makeDefaultExercise(),
      sets: 3,
      setPrescriptions: [
        {
          setIndex: 1,
          prescriptionValue: 10,
          prescriptionUnit: "reps" as const,
          loadValue: 40,
          loadMode: "absolute" as const,
          note: "Controlled",
        },
        {
          setIndex: 2,
          prescriptionValue: 8,
          prescriptionUnit: "reps" as const,
          loadValue: 50,
          loadMode: "absolute" as const,
          note: null,
        },
        {
          setIndex: 3,
          prescriptionValue: 6,
          prescriptionUnit: "reps" as const,
          loadValue: 60,
          loadMode: "absolute" as const,
          note: null,
        },
      ],
      loadProgression: {
        mode: "linear" as const,
        direction: "decrease" as const,
        startValue: 80,
        startMode: "pct_1rm" as const,
        stepValue: 5,
        perSetValues: [],
      },
    };

    expect(concreteSetPrescriptions(exercise)).toEqual([
      expect.objectContaining({
        prescriptionValue: 10,
        loadValue: 80,
        loadMode: "pct_1rm",
        note: "Controlled",
      }),
      expect.objectContaining({ prescriptionValue: 8, loadValue: 75, loadMode: "pct_1rm" }),
      expect.objectContaining({ prescriptionValue: 6, loadValue: 70, loadMode: "pct_1rm" }),
    ]);
  });

  it("does not count a header-only section as executable", () => {
    const section = {
      ...makeDefaultSection(),
      name: "Strength",
      exercises: [{ ...makeDefaultHeader(), name: "Main lifts" }],
    };

    expect(isSectionComplete(section)).toBe(false);
    expect(
      isSectionComplete({
        ...section,
        exercises: [...section.exercises, { ...makeDefaultExercise(), name: "Back squat" }],
      }),
    ).toBe(true);
  });
});
