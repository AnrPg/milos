import { describe, expect, it } from "vitest";

import { groupFinishedWorkouts, type HistoryEntry } from "@/components/client/vault";

const entry = (id: string, workout: string, type: string | null, at: string) =>
  ({
    id,
    master_workout_id: workout,
    workout_title: workout.toUpperCase(),
    workout_type: type,
    completed_at_utc: at,
    day: at.slice(0, 10),
  }) as unknown as HistoryEntry;

describe("groupFinishedWorkouts", () => {
  it("files each workout once under its type, newest first", () => {
    const folders = groupFinishedWorkouts([
      entry("1", "fran", "for_time", "2026-10-01T10:00:00Z"),
      entry("2", "cindy", "amrap", "2026-10-03T10:00:00Z"),
      entry("3", "fran", "for_time", "2026-10-05T10:00:00Z"),
      entry("4", "notes", null, "2026-09-01T10:00:00Z"),
    ]);

    expect(folders.map((folder) => folder.type)).toEqual(["for_time", "amrap", null]);
    expect(folders[0].workouts[0].entries.map((item) => item.id)).toEqual(["3", "1"]);
  });
});
