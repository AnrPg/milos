import { describe, expect, it } from "vitest";

import { distinctOptions, emptyListFilter, listFilterCount, parseListFilter, picked } from "./list-filter";

const SHAPE = { club: "one", type: "many", coaches: "toggle" } as const;

describe("list filters", () => {
  it("starts empty and counts each narrowing field once", () => {
    const empty = emptyListFilter(SHAPE);
    expect(empty).toEqual({ club: [], type: [], coaches: false });
    expect(listFilterCount(empty)).toBe(0);
    expect(listFilterCount({ ...empty, type: ["pr", "event"], coaches: true })).toBe(2);
  });

  it("reads stored params defensively", () => {
    expect(parseListFilter(SHAPE, { club: ["a", "b"], type: ["pr", 3, "pr"], coaches: "yes", other: 1 })).toEqual({
      club: ["a"],
      type: ["pr"],
      coaches: false,
    });
    expect(parseListFilter(SHAPE, null)).toEqual(emptyListFilter(SHAPE));
    expect(parseListFilter(SHAPE, [1, 2])).toEqual(emptyListFilter(SHAPE));
  });

  it("passes everything when nothing is picked", () => {
    expect(picked([], "x")).toBe(true);
    expect(picked(["x"], "x")).toBe(true);
    expect(picked(["x"], null)).toBe(false);
    expect(picked(["x"], ["y", "x"])).toBe(true);
  });

  it("lists distinct options in first-seen order", () => {
    const rows = [
      { id: "b", name: "Beta" },
      { id: "a", name: "" },
      { id: "b", name: "Again" },
      { id: null, name: "None" },
    ];
    expect(distinctOptions(rows, (row) => row.id, (row) => row.name)).toEqual([
      { value: "b", label: "Beta" },
      { value: "a", label: "a" },
    ]);
  });
});
