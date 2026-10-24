import { describe, expect, it } from "vitest";

import { consistencyGrid, heatLevel, heatStrips, weeksOnTarget } from "./consistency";

describe("consistency grid", () => {
  const weekly = [
    { week_start: "2026-10-19", sessions: 3 },
    { week_start: "2026-10-12", sessions: 1 },
  ];
  const days = [
    { date: "2026-10-13", sessions: 1 },
    { date: "2026-10-20", sessions: 2 },
    { date: "2026-10-22", sessions: 1 },
  ];

  it("lays out weeks oldest first, Monday to Sunday, with levels and future days", () => {
    const grid = consistencyGrid(weekly, days, "2026-10-22", 2);
    expect(grid.map((week) => week.week_start)).toEqual(["2026-10-12", "2026-10-19"]);
    expect(grid[0].days.map((day) => day.date)).toEqual([
      "2026-10-12",
      "2026-10-13",
      "2026-10-14",
      "2026-10-15",
      "2026-10-16",
      "2026-10-17",
      "2026-10-18",
    ]);
    expect(grid[0].days[1]).toMatchObject({ sessions: 1, level: 1, future: false });
    expect(grid[1].days[1]).toMatchObject({ sessions: 2, level: 2 });
    expect(grid[1].days.filter((day) => day.future).map((day) => day.date)).toEqual([
      "2026-10-23",
      "2026-10-24",
      "2026-10-25",
    ]);
  });

  it("counts the weeks that reached the target, any session without one", () => {
    expect(weeksOnTarget(consistencyGrid(weekly, days, "2026-10-22", 2))).toBe(1);
    expect(weeksOnTarget(consistencyGrid(weekly, days, "2026-10-22", null))).toBe(2);
    expect(weeksOnTarget(consistencyGrid(weekly, days, "2026-10-22", 0))).toBe(2);
  });

  it("caps the level at three sessions", () => {
    expect([0, 1, 2, 3, 7].map(heatLevel)).toEqual([0, 1, 2, 3, 3]);
  });

  it("wraps long ranges into balanced strips", () => {
    const weeks = consistencyGrid(
      Array.from({ length: 52 }, (_, index) => ({
        week_start: new Date(Date.UTC(2025, 9, 27) + index * 7 * 86_400_000).toISOString().slice(0, 10),
        sessions: 0,
      })),
      [],
      "2026-10-22",
      null,
    );
    expect(heatStrips(weeks).map((strip) => strip.length)).toEqual([26, 26]);
    expect(heatStrips(weeks.slice(0, 30)).map((strip) => strip.length)).toEqual([15, 15]);
    expect(heatStrips(weeks.slice(0, 12)).map((strip) => strip.length)).toEqual([12]);
    expect(heatStrips([])).toEqual([]);
  });
});
