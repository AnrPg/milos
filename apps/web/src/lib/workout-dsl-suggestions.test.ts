import { describe, expect, it } from "vitest";

import {
  buildWorkoutDslSuggestions,
  type WorkoutDslVocabulary,
} from "@/lib/workout-dsl-suggestions";

const vocabulary: WorkoutDslVocabulary = {
  version: 1,
  section_formats: ["untimed", "emom", "complex_emom", "amrap"],
  workout_parameters: ["dsl-version", "title", "type", "!instructions", "!coach-brief"],
  exercise_parameters: ["sets", "reps", "load", "rest-between-sets", "!cue", "!coach-brief"],
  header_parameters: ["title", "subtitle", "!instructions"],
  content_markers: ["!instructions", "!scaling", "!safety", "!equipment", "!cue", "!coach-brief"],
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

  it("updates content-marker suggestions as the user continues typing", () => {
    const source = "[workout]\n!co";
    const result = buildWorkoutDslSuggestions(source, source.length, vocabulary, []);

    expect(result.query).toBe("!co");
    expect(result.items.map((item) => item.value)).toEqual(["!coach-brief"]);
  });

  it("offers a cue only inside an exercise", () => {
    const workout = "[workout]\n!c";
    const exercise = "[workout]\n[section: untimed]\n[exercise: Back Squat]\n!c";

    expect(buildWorkoutDslSuggestions(workout, workout.length, vocabulary, []).items.map((item) => item.value)).toEqual([
      "!coach-brief",
    ]);
    expect(
      buildWorkoutDslSuggestions(exercise, exercise.length, vocabulary, []).items.map((item) => item.value),
    ).toEqual(["!cue", "!coach-brief"]);
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

  it("fuzzily suggests exercises for a misspelled or partial movement name", () => {
    const typoSource = "[exercise: sqt snach";
    const typoResult = buildWorkoutDslSuggestions(
      typoSource,
      typoSource.length,
      vocabulary,
      [],
      ["Air Squat", "Squat Snatch", "Back Extension"],
    );

    expect(typoResult.items[0]).toMatchObject({ value: "Squat Snatch", kind: "exercise" });

    const partialSource = "[exercise: extension";
    const partialResult = buildWorkoutDslSuggestions(
      partialSource,
      partialSource.length,
      vocabulary,
      [],
      ["Air Squat", "Back Extension"],
    );

    expect(partialResult.items[0]?.value).toBe("Back Extension");
  });

  it("keeps contextual DSL keys available on an empty line", () => {
    const source = "[workout]\n[section: untimed]\ntitle: Main\n[exercise: Any Move]\n";
    const result = buildWorkoutDslSuggestions(source, source.length, vocabulary, []);

    expect(result.query).toBe("");
    expect(result.items.map((item) => item.value)).toEqual(
      expect.arrayContaining(["sets", "reps", "load"]),
    );
    expect(result.items.map((item) => item.value)).not.toContain("dsl-version");
  });

  it("narrows slash-command templates by canonical format", () => {
    const source = "/complex";
    const result = buildWorkoutDslSuggestions(source, source.length, vocabulary, []);

    expect(result.query).toBe("complex");
    expect(result.items).toEqual([{ value: "complex_emom", kind: "template" }]);
  });
});
