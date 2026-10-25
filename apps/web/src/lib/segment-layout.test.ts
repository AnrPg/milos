import { describe, expect, it } from "vitest";

import { balancedLineBreak, chooseSegmentLayout, fittingColumns, rowFits } from "./segment-layout";

describe("balancedLineBreak", () => {
  it("keeps one line when every chip fits", () => {
    expect(balancedLineBreak([80, 120, 60, 70], 400, 8)).toBeNull();
    expect(balancedLineBreak([500], 300, 8)).toBeNull();
    expect(balancedLineBreak([80, 120], 0, 8)).toBeNull();
  });

  it("splits into two lines whose wider one is as narrow as possible", () => {
    // 80+8+150 = 238 | 60+8+70 = 138 beats 80 | 150+8+60+8+70.
    expect(balancedLineBreak([80, 150, 60, 70], 288, 8)).toBe(2);
    expect(balancedLineBreak([100, 100, 100], 250, 8)).toBe(2);
    expect(balancedLineBreak([200, 40, 40], 250, 8)).toBe(1);
  });
});

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

describe("rowFits", () => {
  it("fits natural widths that add up within the line", () => {
    expect(rowFits([40, 60, 50], 162, 6)).toBe(true);
    expect(rowFits([40, 60, 50], 161, 6)).toBe(false);
    expect(rowFits([], 0, 6)).toBe(true);
  });

  it("stretched chips need room for the widest one in every share", () => {
    // «All · Coach · Clubs · Partners» at 340px: natural widths fit (290),
    // but four equal shares of ~80px would cut «Partners» (100px).
    const widths = [50, 70, 70, 100];
    expect(rowFits(widths, 340, 6)).toBe(true);
    expect(rowFits(widths, 340, 6, true)).toBe(false);
    expect(rowFits(widths, 418, 6, true)).toBe(true);
  });
});
