import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { ExecutionProgressPayload, WorkoutExecution } from "@/api/executions";
import { ApiError } from "@/api/client";
import { useExecutionStore } from "@/stores/execution";

import { useExecutionSync } from "./useExecutionSync";

const updateExecutionProgress = vi.fn();
const fetchExecution = vi.fn();

vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  updateExecutionProgress: (...args: unknown[]) => updateExecutionProgress(...args),
  fetchExecution: (...args: unknown[]) => fetchExecution(...args),
}));

vi.mock("@/lib/legacy-offline-queue", () => ({ adoptLegacyCheckoffs: () => Promise.resolve(false) }));

function execution(payload: Partial<ExecutionProgressPayload>, lockVersion: number): WorkoutExecution {
  return {
    id: "execution-1",
    lock_version: lockVersion,
    master_workout_id: "workout-1",
    scale_level_slug: null,
    status: "active",
    current_segment_index: 0,
    segment_started_at_utc: null,
    paused_elapsed_ms: 0,
    resume_countdown_ends_at_utc: null,
    total_elapsed_ms: 0,
    section_elapsed_ms: {},
    segment_cycle_counts: {},
    checked_exercise_ids: [],
    section_scores: [],
    comments: [],
    ...payload,
  } as unknown as WorkoutExecution;
}

describe("useExecutionSync", () => {
  beforeEach(() => {
    updateExecutionProgress.mockReset();
    fetchExecution.mockReset();
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      lockVersion: 2,
      workoutId: "workout-1",
      scaleSlug: null,
      segments: [],
      status: "active",
    });
  });

  it("keeps offline check-offs when another device saved first", async () => {
    useExecutionStore.getState().setCheckedExerciseIds(["mine"]);
    updateExecutionProgress
      .mockRejectedValueOnce(new ApiError(409, "conflict", {} as never))
      .mockImplementation((_t: string, _id: string, payload: ExecutionProgressPayload) =>
        Promise.resolve(execution(payload, payload.expected_version + 1)),
      );
    fetchExecution.mockResolvedValue(execution({ checked_exercise_ids: ["theirs"], current_segment_index: 0 }, 5));

    const onProblem = vi.fn();
    const { result } = renderHook(() => useExecutionSync("token", "execution-1", onProblem));
    await act(async () => {
      await result.current.sync();
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    expect(onProblem).toHaveBeenCalledWith("merged");
    const resent = updateExecutionProgress.mock.calls.at(-1)![2] as ExecutionProgressPayload;
    expect(resent.expected_version).toBe(5);
    expect([...resent.checked_exercise_ids].sort()).toEqual(["mine", "theirs"]);
    expect(useExecutionStore.getState().pendingSync).toBe(false);
  });
});
