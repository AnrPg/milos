import { describe, expect, it } from "vitest";

import type { ReviewRecord } from "@/api/reviews";
import type { TrainingLogEntry } from "@/api/training-log";
import type { HistoryEntry } from "@/components/client/vault";

import { journalFlow } from "./journal-flow";

const execution = (id: string, completedAt: string, day: string) =>
  ({ id, completed_at_utc: completedAt, day, workout_title: id }) as unknown as HistoryEntry;
const log = (id: string, performedAt: string, tz = "Europe/Athens") =>
  ({ id, performed_at_utc: performedAt, performed_at_tz: tz, title: id, status: "logged" }) as unknown as TrainingLogEntry;

const review = (id: string, insertedAt: string) =>
  ({ id, inserted_at: insertedAt, target_type: "app", rating: 5 }) as unknown as ReviewRecord;

describe("journalFlow", () => {
  it("merges executions and logged workouts newest first, grouped by the day they were done", () => {
    const days = journalFlow({
      executions: [execution("fran", "2026-10-15T16:00:00Z", "2026-10-15"), execution("grace", "2026-10-13T07:00:00Z", "2026-10-13")],
      logs: [log("park-run", "2026-10-15T05:00:00Z"), log("late-swim", "2026-10-13T22:30:00Z")],
    });

    expect(days.map((day) => [day.day, day.items.map((item) => item.id)])).toEqual([
      ["2026-10-15", ["execution:fran", "log:park-run"]],
      // 22:30 UTC is already the 14th in Athens, where it was logged.
      ["2026-10-14", ["log:late-swim"]],
      ["2026-10-13", ["execution:grace"]],
    ]);
  });

  it("files reviews in the flow by the day they were written", () => {
    const days = journalFlow({
      executions: [execution("fran", "2026-10-15T16:00:00Z", "2026-10-15")],
      logs: [],
      reviews: [review("coach", "2026-10-15T18:00:00Z"), review("app", "2026-10-12T21:30:00Z")],
      fallbackTimeZone: "Europe/Athens",
    });

    expect(days.map((day) => [day.day, day.items.map((item) => `${item.kind}:${item.entry.id}`)])).toEqual([
      ["2026-10-15", ["review:coach", "execution:fran"]],
      ["2026-10-13", ["review:app"]],
    ]);
  });

  it("is empty when nothing was done", () => {
    expect(journalFlow({ executions: [], logs: [] })).toEqual([]);
  });
});
