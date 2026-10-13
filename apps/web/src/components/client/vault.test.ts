import { describe, expect, it } from "vitest";

import type { VaultWorkout } from "@/api/executions";
import {
  entryDay,
  filterVault,
  formatElapsed,
  groupHistoryByDay,
  historyEntries,
} from "@/components/client/vault";

const workouts: VaultWorkout[] = [
  {
    master_workout_id: "w-fran",
    workout_title: "Fran",
    workout_type: "for_time",
    completed_count: 2,
    last_completed_at: "2026-10-10T18:00:00Z",
    entries: [
      { id: "e3", completed_at_utc: "2026-10-10T18:00:00Z", completed_at_tz: "Europe/Athens", source: "repeat", total_elapsed_ms: 300_000 },
      { id: "e1", completed_at_utc: "2026-10-01T07:00:00Z", completed_at_tz: "Europe/Athens", source: "class_booking" },
    ],
  },
  {
    master_workout_id: "w-cindy",
    workout_title: "Cindy",
    workout_type: "amrap",
    completed_count: 1,
    last_completed_at: "2026-10-10T08:00:00Z",
    entries: [
      { id: "e2", completed_at_utc: "2026-10-10T08:00:00Z", completed_at_tz: null, source: "assigned" },
    ],
  },
];

describe("workout vault helpers", () => {
  it("uses the completion timezone for the calendar day", () => {
    // 22:30 UTC is already the next day in Athens.
    expect(entryDay("2026-10-10T22:30:00Z", "Europe/Athens")).toBe("2026-10-11");
    expect(entryDay("2026-10-10T22:30:00Z", "Not/AZone", "UTC")).toBe("2026-10-10");
    expect(entryDay("2026-10-10T22:30:00Z", null, "America/New_York")).toBe("2026-10-10");
  });

  it("flattens every execution into its own entry, newest first, keeping repeats separate", () => {
    const entries = historyEntries(workouts, "UTC");
    expect(entries.map((entry) => entry.id)).toEqual(["e3", "e2", "e1"]);
    expect(entries[0]).toMatchObject({
      master_workout_id: "w-fran",
      workout_title: "Fran",
      source: "repeat",
      day: "2026-10-10",
    });
  });

  it("groups entries by day in order", () => {
    const days = groupHistoryByDay(historyEntries(workouts, "UTC"));
    expect(days.map((day) => [day.day, day.entries.map((entry) => entry.id)])).toEqual([
      ["2026-10-10", ["e3", "e2"]],
      ["2026-10-01", ["e1"]],
    ]);
  });

  it("formats elapsed time and filters the shelf", () => {
    expect(formatElapsed(0)).toBeNull();
    expect(formatElapsed(undefined)).toBeNull();
    expect(formatElapsed(65_000)).toBe("1:05");
    expect(formatElapsed(3_725_000)).toBe("1:02:05");
    expect(filterVault(workouts, " fr ").map((workout) => workout.master_workout_id)).toEqual(["w-fran"]);
    expect(filterVault(workouts, "")).toHaveLength(2);
  });
});
