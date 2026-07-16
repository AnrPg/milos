import { describe, expect, it } from "vitest";

import {
  rebaseQueuedCheckoff,
  type QueuedCheckoff,
} from "@/lib/offline-execution-queue";
import type { WorkoutExecution } from "@/api/executions";

function execution(overrides: Partial<WorkoutExecution> = {}): WorkoutExecution {
  return {
    id: "execution-1",
    user_id: "user-1",
    master_workout_id: "workout-1",
    scale_level_slug: "rx",
    source: "assigned",
    source_reference_id: "assignment-1",
    status: "active",
    started_at_utc: "2026-07-16T10:00:00Z",
    started_at_tz: "Europe/Athens",
    completed_at_utc: null,
    completed_at_tz: null,
    current_segment_index: 3,
    segment_started_at_utc: "2026-07-16T10:05:00Z",
    paused_elapsed_ms: 0,
    resume_countdown_ends_at_utc: null,
    total_elapsed_ms: 12_000,
    section_elapsed_ms: { warmup: 8_000 },
    segment_cycle_counts: { "segment-a": 1 },
    checked_exercise_ids: ["pushups", "squats"],
    section_scores: [{ section_id: "metcon", value: 120, source: "athlete" }],
    exercise_notes: [],
    exercise_modifications: [],
    lock_version: 7,
    inserted_at: "2026-07-16T10:00:00Z",
    ...overrides,
  };
}

describe("rebaseQueuedCheckoff", () => {
  it("rebases queued add and remove operations on the latest server execution", () => {
    const item: QueuedCheckoff = {
      operationId: "op-1",
      executionId: "execution-1",
      createdAt: 1,
      add: ["pullups"],
      remove: ["pushups"],
      payload: {
        operation_id: "op-1",
        expected_version: 3,
        checked_exercise_ids: ["squats", "pullups"],
        current_segment_index: 1,
        status: "active",
        segment_started_at_utc: "stale",
        paused_elapsed_ms: 0,
        resume_countdown_ends_at_utc: null,
        total_elapsed_ms: 20_000,
        section_elapsed_ms: { warmup: 5_000, strength: 10_000 },
        segment_cycle_counts: { "segment-a": 0, "segment-b": 2 },
        section_scores: [],
      },
    };

    const rebased = rebaseQueuedCheckoff(item, execution());

    expect(rebased.expected_version).toBe(7);
    expect(rebased.checked_exercise_ids.sort()).toEqual(["pullups", "squats"]);
    expect(rebased.current_segment_index).toBe(3);
    expect(rebased.segment_started_at_utc).toBe("2026-07-16T10:05:00Z");
    expect(rebased.total_elapsed_ms).toBe(20_000);
    expect(rebased.section_elapsed_ms).toEqual({ warmup: 8_000, strength: 10_000 });
    expect(rebased.segment_cycle_counts).toEqual({ "segment-a": 1, "segment-b": 2 });
    expect(rebased.section_scores).toEqual([{ section_id: "metcon", value: 120, source: "athlete" }]);
  });

  it("preserves paused status when the server is paused", () => {
    const item: QueuedCheckoff = {
      operationId: "op-2",
      executionId: "execution-1",
      createdAt: 2,
      add: ["burpees"],
      remove: [],
      payload: {
        operation_id: "op-2",
        expected_version: 1,
        checked_exercise_ids: ["burpees"],
        current_segment_index: 0,
        status: "active",
        segment_started_at_utc: null,
        paused_elapsed_ms: 0,
        resume_countdown_ends_at_utc: null,
        total_elapsed_ms: 1,
        section_elapsed_ms: {},
        segment_cycle_counts: {},
        section_scores: [],
      },
    };

    expect(rebaseQueuedCheckoff(item, execution({ status: "paused" })).status).toBe("paused");
  });
});
