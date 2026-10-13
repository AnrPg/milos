import { beforeEach, describe, expect, it } from "vitest";

import type { ExecutionProgressPayload, TimerSegment, WorkoutExecution } from "@/api/executions";

import { useExecutionStore } from "./execution";

const segment = (key: string, sectionId: string, extra: Partial<TimerSegment> = {}) =>
  ({
    segment_key: key,
    section_id: sectionId,
    section_name: sectionId,
    format: "for_time",
    kind: "countup",
    duration_seconds: null,
    round: null,
    total_rounds: null,
    label: key,
    scoreable: false,
    score_config: null,
    exercises: [],
    ...extra,
  }) as TimerSegment;

const segments = [
  segment("segment:0", "a"),
  segment("segment:1", "a:rest-after", { kind: "countdown", duration_seconds: 60, between_sections: true }),
  segment("segment:2", "b"),
];

/** What the API stores and echoes back for a progress snapshot. */
function echo(payload: ExecutionProgressPayload, lockVersion: number): WorkoutExecution {
  return {
    id: "execution-1",
    lock_version: lockVersion,
    master_workout_id: "workout-1",
    scale_level_slug: null,
    status: payload.status,
    current_segment_index: payload.current_segment_index,
    segment_started_at_utc: payload.segment_started_at_utc,
    paused_elapsed_ms: payload.paused_elapsed_ms,
    resume_countdown_ends_at_utc: payload.resume_countdown_ends_at_utc,
    total_elapsed_ms: payload.total_elapsed_ms,
    section_elapsed_ms: payload.section_elapsed_ms,
    segment_cycle_counts: payload.segment_cycle_counts,
    checked_exercise_ids: payload.checked_exercise_ids,
    section_scores: payload.section_scores,
    exercise_notes: [],
  } as unknown as WorkoutExecution;
}

function roundTrip(lockVersion: number) {
  const store = useExecutionStore.getState();
  store.hydrateFromExecution(echo(store.buildProgressPayload()!, lockVersion));
}

describe("execution elapsed-time model", () => {
  beforeEach(() => {
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      workoutId: "workout-1",
      scaleSlug: null,
      segments,
      status: "active",
      segmentStartedAt: 0,
    });
  });

  it("does not count time before a pause twice", () => {
    const store = useExecutionStore.getState();

    store.pauseTimer(10_000);
    roundTrip(2);
    expect(useExecutionStore.getState().buildProgressPayload()!.total_elapsed_ms).toBe(10_000);

    useExecutionStore.getState().resumeTimer(100_000);
    roundTrip(3);
    useExecutionStore.getState().moveToSegment(1, {
      elapsedMs: useExecutionStore.getState().currentElapsedMs(105_000),
      startedAt: 105_000,
    });

    expect(useExecutionStore.getState().totalElapsedMs).toBe(15_000);
    expect(useExecutionStore.getState().sectionElapsedMs).toEqual({ a: 15_000 });
  });

  it("keeps between-section rest out of section time but in the workout total", () => {
    useExecutionStore.getState().moveToSegment(1, { elapsedMs: 30_000, startedAt: 30_000 });
    useExecutionStore.getState().moveToSegment(2, { elapsedMs: 60_000, startedAt: 90_000 });

    const state = useExecutionStore.getState();
    expect(state.totalElapsedMs).toBe(90_000);
    expect(state.sectionElapsedMs).toEqual({ a: 30_000 });
  });

  it("commits the segment being left when going back", () => {
    useExecutionStore.getState().moveToSegment(2, { elapsedMs: 20_000, startedAt: 20_000 });
    useExecutionStore.getState().moveToSegment(1, { elapsedMs: 5_000, startedAt: 25_000 });

    expect(useExecutionStore.getState().totalElapsedMs).toBe(25_000);
    expect(useExecutionStore.getState().sectionElapsedMs).toEqual({ a: 20_000, b: 5_000 });
  });

  it("includes the running segment exactly once in completion totals", () => {
    useExecutionStore.getState().pauseTimer(8_000);
    roundTrip(2);
    useExecutionStore.getState().resumeTimer(50_000);

    expect(useExecutionStore.getState().completionTotals(52_000)).toEqual({
      totalElapsedMs: 10_000,
      sectionElapsedMs: { a: 10_000 },
    });
  });

  it("commits segments a catch-up skipped through and starts the next on schedule", () => {
    useExecutionStore.getState().applyCatchUp({
      completed: [
        { index: 0, elapsedMs: 20_000 },
        { index: 1, elapsedMs: 60_000 },
      ],
      index: 2,
      segmentStartedAt: 80_000,
    });

    const state = useExecutionStore.getState();
    expect(state).toMatchObject({ currentSegmentIndex: 2, segmentStartedAt: 80_000, totalElapsedMs: 80_000 });
    expect(state.currentElapsedMs(85_000)).toBe(5_000);
  });
});

describe("conflict rebase", () => {
  beforeEach(() => {
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      lockVersion: 4,
      workoutId: "workout-1",
      scaleSlug: null,
      segments,
      status: "active",
      segmentStartedAt: 0,
      checkedExerciseIds: ["x"],
    });
  });

  it("follows the server timeline and replays local marks on top", () => {
    const store = useExecutionStore.getState();
    store.setCheckedExerciseIds(["x", "y"]);
    store.incrementSegmentCycle("segment:0");
    store.setPendingSync(true);

    const serverPayload = { ...store.buildProgressPayload()!, checked_exercise_ids: ["x", "z"], current_segment_index: 2, segment_cycle_counts: { "segment:0": 3 } };
    const kept = useExecutionStore.getState().rebaseOnto(echo(serverPayload, 6));

    const state = useExecutionStore.getState();
    expect(kept).toBe(true);
    expect(state.lockVersion).toBe(6);
    expect(state.currentSegmentIndex).toBe(2);
    expect([...state.checkedExerciseIds].sort()).toEqual(["x", "y", "z"]);
    expect(state.segmentCycleCounts["segment:0"]).toBe(4);
    expect(state.pendingSync).toBe(true);
  });

  it("has nothing to resend when there were no local marks", () => {
    const store = useExecutionStore.getState();
    const serverPayload = { ...store.buildProgressPayload()!, checked_exercise_ids: ["z"] };
    expect(useExecutionStore.getState().rebaseOnto(echo(serverPayload, 6))).toBe(false);
    expect(useExecutionStore.getState().checkedExerciseIds).toEqual(["z"]);
  });
});

describe("clock adjustments", () => {
  const timed = [segment("segment:0", "a", { kind: "countdown", duration_seconds: 60 }), segment("segment:1", "b")];

  beforeEach(() => {
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      workoutId: "workout-1",
      scaleSlug: null,
      segments: timed,
      status: "paused",
      pausedElapsed: 40_000,
    });
  });

  it("never shortens a clock below what already ran", () => {
    useExecutionStore.getState().adjustSegmentDuration(0, -30);
    expect(useExecutionStore.getState().segments[0]!.duration_seconds).toBe(41);
  });

  it("re-applies adjustments when the sequence is reloaded", () => {
    const store = useExecutionStore.getState();
    store.adjustSegmentDuration(0, 30);
    store.hydrateFromExecution(echo(store.buildProgressPayload()!, 2), timed);
    expect(useExecutionStore.getState().segments[0]!.duration_seconds).toBe(90);

    useExecutionStore.getState().setSegments(timed);
    expect(useExecutionStore.getState().segments[0]!.duration_seconds).toBe(90);
  });
});

describe("clock adjustments across devices", () => {
  const timed = [segment("segment:0", "a", { kind: "countdown", duration_seconds: 60 }), segment("segment:1", "b")];

  beforeEach(() => {
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      lockVersion: 2,
      workoutId: "workout-1",
      scaleSlug: null,
      segments: timed,
      status: "paused",
    });
  });

  it("sends adjustments as deltas and applies the server's on load", () => {
    useExecutionStore.getState().adjustSegmentDuration(0, 30);
    expect(useExecutionStore.getState().buildProgressPayload()!.duration_adjustments).toEqual({ "segment:0": 30 });

    const fromOtherDevice = {
      ...echo(useExecutionStore.getState().buildProgressPayload()!, 3),
      duration_adjustments: { "segment:0": { delta_seconds: 120, authored_seconds: 60 } },
    } as WorkoutExecution;
    useExecutionStore.getState().hydrateFromExecution(fromOtherDevice);

    // Applied to the authored 60 s, not on top of the local +30.
    expect(useExecutionStore.getState().segments[0]!.duration_seconds).toBe(180);
  });

  it("keeps a local adjustment when another device saved first", () => {
    useExecutionStore.getState().adjustSegmentDuration(0, 30);
    const server = {
      ...echo(useExecutionStore.getState().buildProgressPayload()!, 5),
      duration_adjustments: { "segment:0": { delta_seconds: -15, authored_seconds: 60 } },
    } as WorkoutExecution;

    expect(useExecutionStore.getState().rebaseOnto(server)).toBe(true);
    const state = useExecutionStore.getState();
    expect(state.durationAdjustments).toEqual({ "segment:0": 15 });
    expect(state.segments[0]!.duration_seconds).toBe(75);
  });
});
