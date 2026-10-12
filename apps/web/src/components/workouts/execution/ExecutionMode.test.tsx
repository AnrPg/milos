import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { ExecutionProgressPayload, TimerSegment, WorkoutExecution } from "@/api/executions";
import { useExecutionStore } from "@/stores/execution";

import { ExecutionMode } from "./ExecutionMode";

const updateExecutionProgress = vi.fn();

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/i18n/presentation", () => ({
  semanticLabel: (value: string) => value,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

vi.mock("@/lib/realtime", () => ({
  subscribeToTopic: () => () => undefined,
}));

vi.mock("@/lib/offline-execution-queue", () => ({
  isOfflineFailure: () => false,
  queueOfflineCheckoff: vi.fn(),
  reconcileOfflineCheckoffs: () => Promise.resolve(),
}));

vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  updateExecutionProgress: (...args: unknown[]) => updateExecutionProgress(...args),
}));

let lockVersion = 1;

function executionFromPayload(payload: ExecutionProgressPayload): WorkoutExecution {
  lockVersion += 1;
  return {
    id: "execution-1",
    lock_version: lockVersion,
    master_workout_id: "workout-1",
    scale_level_slug: null,
    current_segment_index: payload.current_segment_index,
    status: payload.status,
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

function tabataSegment(index: number, label: string, kind: "work" | "rest"): TimerSegment {
  return {
    segment_key: `segment:${index}`,
    section_id: "tabata",
    section_name: "Tabata",
    format: "tabata",
    kind: "countdown",
    duration_seconds: kind === "work" ? 20 : 10,
    round: 1,
    total_rounds: 2,
    label,
    exercises: kind === "work"
      ? [{ id: "burpee", item_type: "exercise", name: "Burpees", prescription_value: 10, prescription_unit: "reps" }]
      : [],
    scoreable: true,
    score_config: { type: "reps" },
    timer_config: {},
  } as unknown as TimerSegment;
}

const segments = [
  tabataSegment(0, "Work 1/2", "work"),
  tabataSegment(1, "Rest 1/2", "rest"),
  tabataSegment(2, "Work 2/2", "work"),
  {
    ...tabataSegment(3, "Cool down", "rest"),
    section_id: "cooldown",
    section_name: "Cool down",
    format: "rest",
    scoreable: false,
    score_config: null,
  } as TimerSegment,
];

function startAt(index: number) {
  useExecutionStore.getState().initExecution({
    executionId: "execution-1",
    workoutId: "workout-1",
    scaleSlug: null,
    segments,
    currentSegmentIndex: index,
    status: "active",
    segmentStartedAt: Date.now(),
  });
}

describe("ExecutionMode", () => {
  beforeEach(() => {
    lockVersion = 1;
    updateExecutionProgress.mockReset();
    updateExecutionProgress.mockImplementation((_token: string, _id: string, payload: ExecutionProgressPayload) =>
      Promise.resolve(executionFromPayload(payload)),
    );
    useExecutionStore.getState().reset();
  });

  it("does not ask for a score between intervals of a scoreable section", async () => {
    startAt(0);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    });

    await waitFor(() => expect(useExecutionStore.getState().currentSegmentIndex).toBe(1));
    expect(screen.queryByText("theMeasuredScoreIsPrefilledChangeItOnly56e1bc0")).not.toBeInTheDocument();
  });

  it("asks for the score at the end of the section", async () => {
    startAt(2);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    });

    await waitFor(() =>
      expect(screen.getByText("theMeasuredScoreIsPrefilledChangeItOnly56e1bc0")).toBeInTheDocument(),
    );
  });

  it("ends the workout from the pause screen and can return to it", async () => {
    startAt(0);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    });
    await waitFor(() => expect(useExecutionStore.getState().status).toBe("paused"));

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "endWorkoutLabel" }));
    });
    expect(await screen.findByText("logYourScoresaeffd3b")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "backToWorkoutLabel" }));

    expect(await screen.findByRole("button", { name: "resumeb3bd0b5" })).toBeInTheDocument();
    expect(useExecutionStore.getState().status).toBe("paused");
  });
});
