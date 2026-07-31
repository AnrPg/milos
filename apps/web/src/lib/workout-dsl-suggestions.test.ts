import { describe, expect, it } from "vitest";

import {
  buildWorkoutDslSuggestions,
  type WorkoutDslVocabulary,
} from "@/lib/workout-dsl-suggestions";

const vocabulary: WorkoutDslVocabulary = {
  version: 1,
  section_formats: ["untimed", "emom", "complex_emom", "amrap"],
  workout_parameters: ["dsl-version", "title", "type", "!note", "!coach-note"],
  exercise_parameters: ["sets", "reps", "load", "rest-between-sets", "!coach-note"],
  header_parameters: ["title", "subtitle", "!note"],
  note_markers: ["!note", "!coach-note", "!athlete-note"],
  section_parameters: {
    untimed: ["title", "score"],
    emom: ["title", "duration", "interval", "score"],
    complex_emom: ["title", "duration", "interval", "score"],
    amrap: ["title", "duration", "score"],
  },
};

describe("buildWorkoutDslSuggestions", () => {
  it("suggests only matching canonical section formats after a section marker", () => {
    const source = "[workout]\n[section: em";
    const result = buildWorkoutDslSuggestions(source, source.length, vocabulary, []);

    expect(result.query).toBe("em");
    expect(result.items.map((item) => item.value)).toEqual(["emom"]);
    expect(result.items.every((item) => item.kind === "format")).toBe(true);
  });

  it("updates note-marker suggestions as the user continues typing", () => {
    const source = "[workout]\n!co";
    const result = buildWorkoutDslSuggestions(source, source.length, vocabulary, []);

    expect(result.query).toBe("!co");
    expect(result.items.map((item) => item.value)).toEqual(["!coach-note"]);
  });

  it("prioritizes canonical tokens over ordinary workout words", () => {
    const source = "[exercise: Back Squat]\nre";
    const result = buildWorkoutDslSuggestions(
      source,
      source.length,
      vocabulary,
      ["recovery", "repetitions"],
    );

    expect(result.items[0]).toMatchObject({ value: "reps", kind: "canonical" });
    expect(result.items.map((item) => item.value)).toContain("recovery");
  });

  it("suggests exercise names inside an exercise marker", () => {
    const source = "[exercise: back";
    const result = buildWorkoutDslSuggestions(
      source,
      source.length,
      vocabulary,
      [],
      ["Air Squat", "Back Squat", "Back Extension"],
    );

    expect(result.items.map((item) => item.value)).toEqual(["Back Squat", "Back Extension"]);
    expect(result.items.every((item) => item.kind === "exercise")).toBe(true);
  });
});
