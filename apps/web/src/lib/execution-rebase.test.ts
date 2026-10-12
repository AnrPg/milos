import { describe, expect, it } from "vitest";

import { hasMarkChanges, rebaseProgressMarks } from "./execution-rebase";

const base = {
  checkedExerciseIds: ["a", "b"],
  segmentCycleCounts: { "segment:0": 2 },
  sectionScores: [{ section_id: "s1", value: 100 }],
};

describe("rebaseProgressMarks", () => {
  it("replays local check-offs, round deltas and new scores on the server version", () => {
    const local = {
      checkedExerciseIds: ["a", "c"], // removed b, added c
      segmentCycleCounts: { "segment:0": 4 }, // +2 rounds
      sectionScores: [{ section_id: "s1", value: 100 }, { section_id: "s2", value: 12 }],
    };
    const server = {
      checkedExerciseIds: ["a", "b", "d"],
      segmentCycleCounts: { "segment:0": 3, "segment:1": 1 },
      sectionScores: [{ section_id: "s1", value: 110 }],
    };

    const rebased = rebaseProgressMarks(base, local, server);

    expect(rebased.checkedExerciseIds.sort()).toEqual(["a", "c", "d"]);
    expect(rebased.segmentCycleCounts).toEqual({ "segment:0": 5, "segment:1": 1 });
    // s1 was not touched locally, so the server's newer score stays.
    expect(rebased.sectionScores).toEqual([
      { section_id: "s1", value: 110 },
      { section_id: "s2", value: 12 },
    ]);
  });

  it("never lets a removed round push a count below zero", () => {
    const local = { ...base, segmentCycleCounts: { "segment:0": 0 } };
    const server = { ...base, segmentCycleCounts: { "segment:0": 1 } };
    expect(rebaseProgressMarks(base, local, server).segmentCycleCounts["segment:0"]).toBe(0);
  });

  it("detects whether anything changed", () => {
    expect(hasMarkChanges(base, { ...base, checkedExerciseIds: ["b", "a"] })).toBe(false);
    expect(hasMarkChanges(base, { ...base, checkedExerciseIds: ["a"] })).toBe(true);
  });
});
