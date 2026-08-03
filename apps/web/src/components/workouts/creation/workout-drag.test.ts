import { describe, expect, it } from "vitest";

import { resolveWorkoutDragEnd } from "./workout-drag";

describe("resolveWorkoutDragEnd", () => {
  it("moves an exercise using its drag-start metadata when hover unmounts the source card", () => {
    expect(
      resolveWorkoutDragEnd({
        activeId: "exercise-1",
        activeData: {},
        dragStartData: { type: "exercise", sectionId: "section-a" },
        overId: "section-b",
        overData: { type: "section" },
      }),
    ).toEqual({
      type: "move-exercise",
      exerciseId: "exercise-1",
      fromSectionId: "section-a",
      toSectionId: "section-b",
    });
  });

  it("moves an exercise onto an exercise in another section", () => {
    expect(
      resolveWorkoutDragEnd({
        activeId: "exercise-1",
        activeData: { type: "exercise", sectionId: "section-a" },
        dragStartData: null,
        overId: "exercise-2",
        overData: { type: "exercise", sectionId: "section-b" },
      }),
    ).toEqual({
      type: "move-exercise",
      exerciseId: "exercise-1",
      fromSectionId: "section-a",
      toSectionId: "section-b",
    });
  });
});
