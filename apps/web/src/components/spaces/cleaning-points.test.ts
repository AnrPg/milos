import { describe, expect, it } from "vitest";

import { answerReady, firstUnanswered, resultCounts, toPointResults } from "@/components/spaces/cleaning-points";

const points = [{ id: "a" }, { id: "b" }];

describe("cleaning point answers", () => {
  it("needs a status, and a note when not cleaned", () => {
    expect(answerReady(undefined)).toBe(false);
    expect(answerReady({ status: "cleaned" })).toBe(true);
    expect(answerReady({ status: "not_cleaned", note: "  " })).toBe(false);
    expect(answerReady({ status: "not_cleaned", note: "No spray" })).toBe(true);
  });

  it("finds the first point still to answer", () => {
    expect(firstUnanswered(points, {})).toBe(0);
    expect(firstUnanswered(points, { a: { status: "cleaned" } })).toBe(1);
    expect(firstUnanswered(points, { a: { status: "cleaned" }, b: { status: "not_cleaned", note: "x" } })).toBe(-1);
  });

  it("builds the API results in the points' order", () => {
    expect(
      toPointResults(points, {
        b: { status: "not_cleaned", note: " No spray " },
        a: { status: "cleaned", afterMediaId: "m1" },
      }),
    ).toEqual([
      { point_id: "a", status: "cleaned", note: null, after_media_id: "m1" },
      { point_id: "b", status: "not_cleaned", note: "No spray", after_media_id: null },
    ]);
  });

  it("counts cleaned and not cleaned", () => {
    expect(resultCounts([{ status: "cleaned" }, { status: "not_cleaned" }, { status: "cleaned" }])).toEqual({ cleaned: 2, notCleaned: 1 });
    expect(resultCounts(undefined)).toEqual({ cleaned: 0, notCleaned: 0 });
  });
});
