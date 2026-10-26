import { describe, expect, it } from "vitest";

import { dueStatus, orderDue, parseTimes, placementSummary, progress, shortTime } from "./cleaning-today";
import {
  groupByBranch,
  labelPosition,
  normalizedPoint,
  rectangleFromDrag,
  spacesOnPlan,
  svgPoints,
  upcomingWindow,
  validArea,
  windowReady,
} from "./floor-plan";

describe("floor plan geometry (ADR-202)", () => {
  it("normalizes a pointer over the plan and clamps it to the image", () => {
    const box = { left: 100, top: 50, width: 400, height: 200 };
    expect(normalizedPoint(300, 150, box)).toEqual([0.5, 0.5]);
    expect(normalizedPoint(50, 400, box)).toEqual([0, 1]);
    expect(normalizedPoint(0, 0, { left: 0, top: 0, width: 0, height: 0 })).toEqual([0, 0]);
  });

  it("turns a drag into a rectangle in any direction, ignoring clicks", () => {
    expect(rectangleFromDrag([0.6, 0.5], [0.2, 0.1])).toEqual([
      [0.2, 0.1],
      [0.6, 0.1],
      [0.6, 0.5],
      [0.2, 0.5],
    ]);
    expect(rectangleFromDrag([0.2, 0.2], [0.205, 0.5])).toBeNull();
  });

  it("draws areas on a 100×100 viewBox with the label in the middle", () => {
    const points = [
      [0.1, 0.2],
      [0.5, 0.2],
      [0.5, 0.6],
      [0.1, 0.6],
    ];
    expect(svgPoints(points)).toBe("10,20 50,20 50,60 10,60");
    expect(labelPosition(points)).toEqual({ x: 30, y: 40 });
  });

  it("keeps only the spaces drawn on a plan", () => {
    const area = { points: [[0, 0], [1, 0], [1, 1]] };
    const spaces = [
      { id: "a", floor_plan_id: "p1", area },
      { id: "b", floor_plan_id: "p1", area: null },
      { id: "c", floor_plan_id: "p2", area },
      { id: "d", floor_plan_id: "p1", area: { points: [[0, 0], [2, 0], [1, 1]] } },
    ];
    expect(spacesOnPlan(spaces, "p1").map((space) => space.id)).toEqual(["a"]);
    expect(validArea(null)).toBe(false);
  });

  it("groups spaces by branch in the branches' order, with the gym-wide group last", () => {
    const groups = groupByBranch(
      [
        { id: "1", location_id: null },
        { id: "2", location_id: "marousi" },
        { id: "3", location_id: "kifisia" },
      ],
      ["kifisia", "marousi", "empty"],
    );
    expect(groups.map((group) => [group.locationId, group.items.map((item) => item.id)])).toEqual([
      ["kifisia", ["3"]],
      ["marousi", ["2"]],
      ["empty", []],
      [null, ["1"]],
    ]);
  });

  it("reads unavailability windows", () => {
    const now = new Date("2026-12-01T10:00:00Z");
    expect(upcomingWindow({ ends_at: "2026-12-01T11:00:00Z" }, now)).toBe(true);
    expect(upcomingWindow({ ends_at: "2026-12-01T09:00:00Z" }, now)).toBe(false);
    expect(windowReady("2026-12-01T10:00:00Z", "2026-12-01T12:00:00Z")).toBe(true);
    expect(windowReady("2026-12-01T10:00:00Z", "2026-12-01T10:00:00Z")).toBe(false);
    expect(windowReady(null, "2026-12-01T10:00:00Z")).toBe(false);
  });
});

describe("the cleaning list of today (ADR-202)", () => {
  const rows = [
    { space_id: "showers", cleanings_due: 2, cleanings_done: 2, done: true },
    { space_id: "mats", cleanings_due: 1, cleanings_done: 0, done: false },
    { space_id: "cardio", cleanings_due: 1, cleanings_done: 0, done: false },
  ];

  it("shows what is in progress first, then what is due, then what is done", () => {
    const open = [{ id: "e1", area_id: "cardio" }];
    expect(dueStatus(rows[1], open)).toBe("due");
    expect(dueStatus(rows[2], open)).toBe("in_progress");
    expect(dueStatus(rows[0], [])).toBe("done");
    expect(orderDue(rows, open).map((row) => row.space_id)).toEqual(["cardio", "mats", "showers"]);
    expect(progress(rows)).toEqual({ done: 1, total: 3 });
  });

  it("reads schedule times", () => {
    expect(shortTime("07:00:00")).toBe("07:00");
    expect(parseTimes("21:30, 07:00 07:00")).toEqual(["07:00", "21:30"]);
    expect(parseTimes("")).toEqual([]);
    expect(parseTimes("7am")).toBeNull();
    expect(parseTimes("24:00")).toBeNull();
  });

  it("sums machine placements against what is owned", () => {
    expect(placementSummary(6, [{ quantity: 5 }, { quantity: 1 }])).toEqual({ placed: 6, unassigned: 0, fits: true });
    expect(placementSummary(6, [{ quantity: 4 }])).toEqual({ placed: 4, unassigned: 2, fits: true });
    expect(placementSummary(1, [{ quantity: 2 }])).toEqual({ placed: 2, unassigned: 0, fits: false });
    expect(placementSummary(3, [{ quantity: Number.NaN }])).toEqual({ placed: 0, unassigned: 3, fits: true });
  });
});
