import { beforeEach, describe, expect, it } from "vitest";

import { useScheduleStore } from "./schedule";

describe("useScheduleStore", () => {
  beforeEach(() => useScheduleStore.setState({ days: 30, startDate: "2026-10-01" }));

  it("openDay switches to the day view of that date", () => {
    useScheduleStore.getState().openDay("2026-10-14");

    expect(useScheduleStore.getState()).toMatchObject({ days: 1, startDate: "2026-10-14" });
  });

  it("the day view steps one day at a time", () => {
    useScheduleStore.getState().openDay("2026-10-31");
    useScheduleStore.getState().shiftWindow(1);
    expect(useScheduleStore.getState().startDate).toBe("2026-11-01");

    useScheduleStore.getState().shiftWindow(-1);
    useScheduleStore.getState().shiftWindow(-1);
    expect(useScheduleStore.getState().startDate).toBe("2026-10-30");
  });
});
