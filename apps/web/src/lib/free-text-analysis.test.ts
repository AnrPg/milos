import { describe, expect, it } from "vitest";

import type { FreeTextWorkoutAnalysis } from "@/api/workouts";
import {
  acceptIssue,
  addSuggestion,
  blockingProblems,
  createReviewState,
  describePath,
  parseFieldInput,
  publishFields,
  rejectIssue,
  replaceFirst,
  undoIssue,
} from "./free-text-analysis";

function analysis(): FreeTextWorkoutAnalysis {
  return {
    workout: {
      title: "Murph prep",
      type: "crossfit",
      difficulty: null,
      equipment: [],
      sections: [
        {
          name: "Main",
          note: null,
          timer_config: { type: "for_time", rounds: 5 },
          exercises: [
            { name: "pul ups", item_type: "exercise", prescription_value: 10, prescription_unit: "reps", load_value: null, load_mode: null },
            { name: "Back squat", item_type: "exercise", sets: 5, prescription_value: 5, prescription_unit: "reps", load_value: 102, load_mode: "absolute" },
          ],
        },
      ],
    },
    issues: [
      {
        id: "issue-1",
        path: "sections.0.exercises.0.name",
        code: "assistant",
        severity: "warning",
        required: true,
        params: {},
        message: "Typo",
        current_value: "pul ups",
        suggestion: { label: "Fix", value: "pull ups", text_edit: { find: "pul ups", replace: "pull ups" } },
      },
      {
        id: "issue-2",
        path: "sections.0.exercises.1.load_value",
        code: "assistant",
        severity: "warning",
        required: false,
        params: {},
        message: "225 lb is 102 kg",
        current_value: 102,
        suggestion: { label: "Use 100 kg", value: 100, text_edit: null },
      },
    ],
    suggestions: [{ id: "suggestion-1", path: "difficulty", field: "difficulty", reason: "Helps athletes", value: "advanced", text_insert: null }],
    summary: { sections: 1, exercises: 2, errors: 0, warnings: 2, blocking: 0 },
  };
}

describe("free text review state", () => {
  it("accepting writes the suggested value", () => {
    const state = acceptIssue(createReviewState(analysis(), "text"), analysis().issues[0]);
    expect(state.workout.sections[0].exercises[0].name).toBe("pull ups");
    expect(state.issues["issue-1"]).toBe("accepted");
  });

  it("rejecting a required field nullifies it and blocks creation", () => {
    const state = rejectIssue(createReviewState(analysis(), "text"), analysis().issues[0]);
    expect(state.workout.sections[0].exercises[0].name).toBeNull();
    expect(blockingProblems("Murph prep", "crossfit", state)).toEqual([
      { path: "sections.0.exercises.0.name", reason: "required" },
    ]);
  });

  it("rejecting an optional field clears paired fields and keeps creation possible", () => {
    const state = rejectIssue(createReviewState(analysis(), "text"), analysis().issues[1]);
    const squat = state.workout.sections[0].exercises[1];
    expect(squat.load_value).toBeNull();
    expect(squat.load_mode).toBeNull();
    expect(blockingProblems("Murph prep", "crossfit", state)).toEqual([]);
  });

  it("undo restores the analyzed value", () => {
    const base = createReviewState(analysis(), "text");
    const state = undoIssue(rejectIssue(base, analysis().issues[1]), analysis().issues[1]);
    expect(state.workout.sections[0].exercises[1].load_value).toBe(102);
    expect(state.workout.sections[0].exercises[1].load_mode).toBe("absolute");
    expect(state.issues["issue-2"]).toBeUndefined();
  });

  it("suggestions add canonical values and publish fields omit empties", () => {
    const state = addSuggestion(createReviewState(analysis(), "text"), analysis().suggestions[0], "advanced");
    const fields = publishFields(state);
    expect(fields.difficulty).toBe("advanced");
    expect(fields.sections[0]).not.toHaveProperty("note");
    expect(fields.sections[0].exercises[0]).not.toHaveProperty("load_value");
  });

  it("validates title and type without an analysis", () => {
    expect(blockingProblems(" ", "spinning", null)).toEqual([
      { path: "title", reason: "required" },
      { path: "type", reason: "required" },
    ]);
    expect(blockingProblems("Ab", "strength", null)).toEqual([{ path: "title", reason: "too_short" }]);
  });
});

describe("helpers", () => {
  it("describes paths for humans", () => {
    expect(describePath("sections.1.exercises.2.tempo")).toEqual({ section: 2, exercise: 3, field: "tempo" });
    expect(describePath("difficulty")).toEqual({ field: "difficulty" });
  });

  it("parses typed values per field", () => {
    expect(parseFieldInput("estimated_duration_seconds", "45")).toBe(2700);
    expect(parseFieldInput("equipment", "bar, rings ,")).toEqual(["bar", "rings"]);
    expect(parseFieldInput("sections.0.exercises.0.sets", "x")).toBeUndefined();
    expect(parseFieldInput("type", "Strength")).toBe("strength");
  });

  it("replaces only verbatim text", () => {
    expect(replaceFirst("10 pul ups", "pul ups", "pull ups")).toBe("10 pull ups");
    expect(replaceFirst("10 pull ups", "pul  ups", "x")).toBeNull();
  });
});
