import { describe, expect, it } from "vitest";

import type { StaffWorkoutGoalsResponse } from "@/api/wod-goals";

import {
  cycleMuscleRole,
  differsFromSuggestion,
  feltHighlights,
  goalHighlights,
  goalPanelReducer,
  hasUnsavedChanges,
  initialGoalPanelState,
  insertPhrase,
  musclesByRole,
  nextRole,
  savePayload,
  searchKey,
  searchMuscleTree,
  STIMULUS_MAX_LENGTH,
  summaryMuscleIds,
  timeDomainLabel,
} from "./goals";

function response(overrides: {
  goals?: Partial<StaffWorkoutGoalsResponse["goals"]>;
  suggestion?: Partial<StaffWorkoutGoalsResponse["suggestion"]>;
} = {}): StaffWorkoutGoalsResponse {
  const muscles = [{ id: "quadriceps", role: "primary" as const }, { id: "glutes", role: "secondary" as const }];
  return {
    goals: {
      workout_id: "w-1",
      saved: false,
      muscles,
      qualities: ["stamina"],
      stimulus: null,
      visible_to_members: false,
      source: "suggested",
      taxonomy_version: 1,
      updated_by_id: null,
      updated_at: null,
      ...overrides.goals,
    },
    suggestion: { muscles, qualities: ["stamina"], matched_exercises: 2, unmatched_exercises: 0, taxonomy_version: 1, ...overrides.suggestion },
  };
}

describe("roles", () => {
  it("cycles primary → secondary → stabilizer → off", () => {
    expect(nextRole(null)).toBe("primary");
    expect(nextRole("primary")).toBe("secondary");
    expect(nextRole("secondary")).toBe("stabilizer");
    expect(nextRole("stabilizer")).toBeNull();
    let muscles = cycleMuscleRole([], "glutes");
    expect(muscles).toEqual([{ id: "glutes", role: "primary" }]);
    muscles = cycleMuscleRole(cycleMuscleRole(cycleMuscleRole(muscles, "glutes"), "glutes"), "glutes");
    expect(muscles).toEqual([]);
  });

  it("groups by role and builds highlights", () => {
    const muscles = [
      { id: "glutes", role: "stabilizer" as const },
      { id: "quadriceps", role: "primary" as const },
      { id: "nope", role: "primary" as const },
    ];
    expect(musclesByRole(muscles).map(([role]) => role)).toEqual(["primary", "stabilizer"]);
    expect(goalHighlights(muscles, ["primary", "secondary"])).toEqual({ quadriceps: "primary" });
    expect(feltHighlights(muscles, ["glutes"])).toEqual({ quadriceps: "primary", glutes: "felt" });
  });

  it("names up to three primary groups, heads by their group", () => {
    expect(
      summaryMuscleIds([
        { id: "deltoid-anterior", role: "primary" },
        { id: "deltoid-lateral", role: "primary" },
        { id: "glutes", role: "secondary" },
        { id: "quadriceps", role: "primary" },
        { id: "latissimus-dorsi", role: "primary" },
        { id: "rhomboids", role: "primary" },
      ]),
    ).toEqual(["deltoid", "quadriceps", "latissimus-dorsi"]);
  });
});

describe("coach panel state", () => {
  it("follows the suggestion while unsaved and nothing is edited", () => {
    let state = goalPanelReducer(initialGoalPanelState, { type: "loaded", response: response() });
    expect(state.following).toBe(true);
    expect(hasUnsavedChanges(state)).toBe(false);
    state = goalPanelReducer(state, {
      type: "loaded",
      response: response({ suggestion: { muscles: [{ id: "hamstrings", role: "primary" }], qualities: ["strength"], matched_exercises: 3 } }),
    });
    expect(state.draft.muscles).toEqual([{ id: "hamstrings", role: "primary" }]);
    expect(state.suggestion?.matched).toBe(3);
    // Members never see an unsaved suggestion, so following alone saves nothing.
    expect(hasUnsavedChanges(state)).toBe(false);
  });

  it("keeps the coach's edits and only moves the reset target", () => {
    let state = goalPanelReducer(initialGoalPanelState, { type: "loaded", response: response() });
    state = goalPanelReducer(state, { type: "cycleRole", id: "glutes" });
    expect(state.draft.muscles).toContainEqual({ id: "glutes", role: "stabilizer" });
    expect(state.following).toBe(false);
    expect(hasUnsavedChanges(state)).toBe(true);
    state = goalPanelReducer(state, {
      type: "loaded",
      response: response({ suggestion: { muscles: [{ id: "hamstrings", role: "primary" }] } }),
    });
    expect(state.draft.muscles).toContainEqual({ id: "glutes", role: "stabilizer" });
    expect(state.suggestion?.muscles).toEqual([{ id: "hamstrings", role: "primary" }]);
    expect(differsFromSuggestion(state)).toBe(true);

    state = goalPanelReducer(state, { type: "resetToSuggestion" });
    expect(state.draft.muscles).toEqual([{ id: "hamstrings", role: "primary" }]);
    expect(state.following).toBe(true);
    expect(differsFromSuggestion(state)).toBe(false);
  });

  it("loads edited saved goals without following, and tracks saved revisions", () => {
    let state = goalPanelReducer(initialGoalPanelState, {
      type: "loaded",
      response: response({ goals: { saved: true, source: "edited", muscles: [{ id: "glutes", role: "primary" }], visible_to_members: true, stimulus: "fast" } }),
    });
    expect(state.following).toBe(false);
    expect(state.draft.visible).toBe(true);
    expect(state.draft.stimulus).toBe("fast");
    state = goalPanelReducer(state, { type: "setVisible", visible: false });
    expect(hasUnsavedChanges(state)).toBe(true);
    state = goalPanelReducer(state, { type: "savedRevision", revision: state.revision });
    expect(hasUnsavedChanges(state)).toBe(false);
    expect(savePayload(state.draft)).toEqual({
      muscles: [{ id: "glutes", role: "primary" }],
      qualities: ["stamina"],
      stimulus: "fast",
      visible_to_members: false,
    });
  });

  it("re-saves stored suggested goals when the suggestion moves", () => {
    let state = goalPanelReducer(initialGoalPanelState, { type: "loaded", response: response({ goals: { saved: true } }) });
    expect(hasUnsavedChanges(state)).toBe(false);
    state = goalPanelReducer(state, { type: "loaded", response: response({ goals: { saved: true }, suggestion: { qualities: ["power"] } }) });
    expect(state.draft.qualities).toEqual(["power"]);
    expect(hasUnsavedChanges(state)).toBe(true);
  });
});

describe("stimulus", () => {
  it("inserts phrases with commas within the limit", () => {
    expect(insertPhrase("", "βαρύ")).toBe("βαρύ");
    expect(insertPhrase("γρήγορο, ", "βαρύ")).toBe("γρήγορο, βαρύ");
    expect(insertPhrase("x".repeat(STIMULUS_MAX_LENGTH), "βαρύ")).toHaveLength(STIMULUS_MAX_LENGTH);
    expect(timeDomainLabel(720)).toBe("12′");
    expect(timeDomainLabel(null)).toBeNull();
    expect(savePayload({ muscles: [], qualities: [], stimulus: "  ", visible: false }).stimulus).toBeNull();
  });
});

describe("picker search", () => {
  it("filters regions, keeping a group whose head matches", () => {
    const tree = searchMuscleTree((id) => id === "deltoid-anterior");
    expect(tree).toEqual([{ region: "shoulders", rows: [{ id: "deltoid", kind: "group" }, { id: "deltoid-anterior", kind: "head" }] }]);
    expect(searchKey("Τετρακέφαλος")).toBe("τετρακεφαλος");
  });
});
