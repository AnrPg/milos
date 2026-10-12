import { describe, expect, it } from "vitest";

import type { FreeTextWorkoutAnalysis } from "@/api/workouts";
import {
  acceptIssue,
  addSuggestion,
  blockingProblems,
  createReviewState,
  describePath,
  isAssumptionIssue,
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

  it("marks timers incomplete until an uninferred timer issue is rejected", () => {
    const base = analysis();
    const timerIssue = {
      id: "issue-3",
      path: "sections.0.timer_config",
      code: "invalid_timer",
      severity: "warning",
      required: false,
      params: { format: "emom", missing: ["interval_seconds"] },
      message: null,
      current_value: null,
      suggestion: null,
    };
    base.issues.push(timerIssue as (typeof base.issues)[number]);
    const state = createReviewState(base, "text");
    expect(publishFields(state).workout_metadata).toEqual({ timer_inference: "incomplete" });
    const rejected = rejectIssue(state, base.issues[2]);
    expect(publishFields(rejected).workout_metadata).toEqual({ timer_inference: "complete" });
    expect(publishFields(createReviewState(analysis(), "text")).workout_metadata).toEqual({ timer_inference: "complete" });
  });

  it("rejecting a proofreading correction keeps the field; text-only fixes never touch fields", () => {
    const base = analysis();
    const nameFix = { ...base.issues[0], id: "c1", code: "text_correction" };
    const textFix = {
      ...base.issues[0],
      id: "c2",
      code: "text_correction",
      path: "text",
      required: false,
      suggestion: { label: "Add min", value: null, text_edit: { find: "cap 12", replace: "cap 12 min" } },
    };
    base.issues = [nameFix, textFix];
    const state = createReviewState(base, "text");

    const rejected = rejectIssue(state, nameFix);
    expect(rejected.workout.sections[0].exercises[0].name).toBe("pul ups");
    expect(blockingProblems("Murph prep", "crossfit", rejected)).toEqual([]);

    const accepted = acceptIssue(state, textFix);
    expect(accepted.workout).toEqual(state.workout);
    expect(accepted.issues.c2).toBe("accepted");
    expect(undoIssue(accepted, textFix).workout).toEqual(state.workout);
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

describe("assumptions", () => {
  const assumption = {
    id: "issue-9",
    path: "sections.0.timer_config",
    code: "assumption",
    severity: "info" as const,
    required: false,
    params: {},
    message: "Read 5 rounds as for time.",
    current_value: { type: "for_time", rounds: 5 },
    suggestion: { label: null, value: { type: "for_time", rounds: 5 }, text_edit: null },
  };

  it("keeps the inferred value on accept and clears it on reject", () => {
    const state = createReviewState({ ...analysis(), issues: [assumption] }, "text");
    expect(isAssumptionIssue(assumption)).toBe(true);

    const kept = acceptIssue(state, assumption);
    expect(kept.workout.sections[0]?.timer_config).toEqual({ type: "for_time", rounds: 5 });

    const rejected = rejectIssue(state, assumption);
    expect(rejected.workout.sections[0]?.timer_config).toBeNull();
    expect(rejected.issues["issue-9"]).toBe("rejected");
  });
});
