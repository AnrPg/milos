import { describe, expect, it } from "vitest";

import type { TimerSegment } from "@/api/executions";

import { buildSegmentStepDefinitions, isLastSegmentOfSection } from "./progress";

function segment(exercises: TimerSegment["exercises"]): TimerSegment {
  return {
    segment_key: "segment:0",
    section_id: "section-1",
    section_name: "Main work",
    format: "for_time",
    kind: "countup",
    duration_seconds: null,
    round: null,
    total_rounds: null,
    label: "Main work",
    scoreable: false,
    score_config: null,
    exercises,
  };
}

function exercise(
  id: string,
  attrs: Partial<TimerSegment["exercises"][number]> = {},
): TimerSegment["exercises"][number] {
  return {
    id,
    item_type: "exercise",
    name: id,
    sets: 2,
    prescription_value: 10,
    prescription_unit: "reps",
    ...attrs,
  };
}

describe("buildSegmentStepDefinitions", () => {
  it("keeps headers non-actionable and interleaves every member of a superset by set", () => {
    const steps = buildSegmentStepDefinitions(
      segment([
        exercise("header", { item_type: "header" }),
        exercise("a", { superset_group_id: "group-1" }),
        exercise("b", { superset_group_id: "group-1" }),
      ]),
    );

    expect(steps.map((step) => `${step.exercise.id}:${step.setNumber}`)).toEqual([
      "a:1",
      "b:1",
      "a:2",
      "b:2",
    ]);
    expect(steps.every((step) => step.groupKind === "superset")).toBe(true);
  });

  it("supports alternating groups larger than two and uses per-set repetitions", () => {
    const perSet = (values: number[]) =>
      values.map((value, index) => ({
        set_index: index + 1,
        prescription_value: value,
        prescription_unit: "reps",
      }));

    const steps = buildSegmentStepDefinitions(
      segment([
        exercise("a", { alternating_group_id: "group-2", set_prescriptions: perSet([12, 8]) }),
        exercise("b", { alternating_group_id: "group-2", set_prescriptions: perSet([10, 6]) }),
        exercise("c", { alternating_group_id: "group-2", set_prescriptions: perSet([8, 4]) }),
      ]),
    );

    expect(steps.map((step) => `${step.exercise.id}:${step.setPrescription?.prescription_value}`)).toEqual([
      "a:12",
      "b:10",
      "c:8",
      "a:8",
      "b:6",
      "c:4",
    ]);
    expect(steps.every((step) => step.groupKind === "alternating")).toBe(true);
  });
});

describe("isLastSegmentOfSection", () => {
  const tabata = (key: string, sectionId = "tabata") => ({
    ...segment([]),
    segment_key: key,
    section_id: sectionId,
  });
  const segments = [tabata("work-1"), tabata("rest-1"), tabata("work-2"), tabata("cooldown", "cooldown")];

  it("is false for intervals inside a multi-segment section", () => {
    expect(isLastSegmentOfSection(segments, 0)).toBe(false);
    expect(isLastSegmentOfSection(segments, 1)).toBe(false);
  });

  it("is true for the final segment of a section and of the workout", () => {
    expect(isLastSegmentOfSection(segments, 2)).toBe(true);
    expect(isLastSegmentOfSection(segments, 3)).toBe(true);
  });

  it("is false for an out-of-range index", () => {
    expect(isLastSegmentOfSection(segments, 9)).toBe(false);
  });
});
