import { describe, expect, it } from "vitest";

import { chooseSegmentLayout, fittingColumns } from "./segment-layout";

describe("fittingColumns", () => {
  it("counts equal columns including the gaps between them", () => {
    expect(fittingColumns(380, 120, 8)).toBe(3);
    expect(fittingColumns(240, 120, 8)).toBe(1);
    expect(fittingColumns(248, 120, 8)).toBe(2);
  });

  it("is zero before anything is measured", () => {
    expect(fittingColumns(0, 120, 8)).toBe(0);
    expect(fittingColumns(300, 0, 8)).toBe(0);
  });
});

describe("chooseSegmentLayout", () => {
  it("keeps one row when every chip fits", () => {
    expect(chooseSegmentLayout({ count: 4, rowFits: true, columns: 4 })).toEqual({ kind: "row" });
    expect(chooseSegmentLayout({ count: 1, rowFits: false, columns: 0 })).toEqual({ kind: "row" });
  });

  it("uses a grid only when the chips fill it", () => {
    expect(chooseSegmentLayout({ count: 4, rowFits: false, columns: 2 })).toEqual({ kind: "grid", columns: 2, rows: 2 });
    expect(chooseSegmentLayout({ count: 6, rowFits: false, columns: 3 })).toEqual({ kind: "grid", columns: 3, rows: 2 });
    expect(chooseSegmentLayout({ count: 6, rowFits: false, columns: 2 })).toEqual({ kind: "grid", columns: 2, rows: 3 });
  });

  it("prefers the widest full grid", () => {
    expect(chooseSegmentLayout({ count: 6, rowFits: false, columns: 5 })).toEqual({ kind: "grid", columns: 3, rows: 2 });
  });

  it("falls back to a dropdown when no grid is full", () => {
    expect(chooseSegmentLayout({ count: 3, rowFits: false, columns: 2 })).toEqual({ kind: "select" });
    expect(chooseSegmentLayout({ count: 5, rowFits: false, columns: 4 })).toEqual({ kind: "select" });
    expect(chooseSegmentLayout({ count: 7, rowFits: false, columns: 6 })).toEqual({ kind: "select" });
  });

  it("falls back to a dropdown when the grid would be too tall or nothing fits", () => {
    expect(chooseSegmentLayout({ count: 8, rowFits: false, columns: 2 })).toEqual({ kind: "select" });
    expect(chooseSegmentLayout({ count: 4, rowFits: false, columns: 1 })).toEqual({ kind: "select" });
  });
});
