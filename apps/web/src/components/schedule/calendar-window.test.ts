import { describe, expect, it } from "vitest";

import { buildScheduleWindow } from "./calendar-window";

describe("buildScheduleWindow", () => {
  it("the day view covers that one day on the gym's clock", () => {
    const window = buildScheduleWindow("2026-10-28", 1, "UTC");

    expect(window.visibleDates).toEqual(["2026-10-28"]);
    expect(window.queryStartAt).toBe("2026-10-28T00:00:00.000Z");
    expect(window.queryEndAt).toBe("2026-10-29T00:00:00.000Z");
    expect(window.monthLabel).toBeNull();
  });

  it("the month view anchored on a day covers that day's month", () => {
    const window = buildScheduleWindow("2026-10-28", 30, "UTC");

    expect(window.visibleDates).toContain("2026-10-28");
    expect(window.queryStartAt).toBe("2026-10-01T00:00:00.000Z");
    expect(window.queryEndAt).toBe("2026-11-01T00:00:00.000Z");
  });
});
