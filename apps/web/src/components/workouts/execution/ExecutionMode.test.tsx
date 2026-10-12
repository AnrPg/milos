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

vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  updateExecutionProgress: (...args: unknown[]) => updateExecutionProgress(...args),
}));

let lockVersion = 3;

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

function startAt(index: number, extra: { segments?: TimerSegment[]; segmentStartedAt?: number } = {}) {
  useExecutionStore.getState().initExecution({
    executionId: "execution-1",
    // Past the ready screen: the workout has already been started.
    lockVersion: 3,
    workoutId: "workout-1",
    scaleSlug: null,
    segments: extra.segments ?? segments,
    currentSegmentIndex: index,
    status: "active",
    segmentStartedAt: extra.segmentStartedAt ?? Date.now(),
  });
}

describe("ExecutionMode", () => {
  beforeEach(() => {
    lockVersion = 3;
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
      fireEvent.click(screen.getByRole("button", { name: "nextbc98198" }));
    });

    await waitFor(() => expect(useExecutionStore.getState().currentSegmentIndex).toBe(1));
    expect(screen.queryByText("theMeasuredScoreIsPrefilledChangeItOnly56e1bc0")).not.toBeInTheDocument();
  });

  it("asks for the score at the end of the section", async () => {
    startAt(2);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "nextbc98198" }));
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

  it("shows the ready screen for a fresh execution and starts with a get-ready countdown", async () => {
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      workoutId: "workout-1",
      scaleSlug: null,
      segments,
      status: "active",
      segmentStartedAt: Date.now() - 60_000,
    });
    render(<ExecutionMode />);

    expect(screen.getByText("readyTitle")).toBeInTheDocument();

    const before = Date.now();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "start952f375" }));
    });

    const state = useExecutionStore.getState();
    expect(state.status).toBe("paused");
    expect(state.pausedElapsed).toBe(0);
    expect(state.resumeCountdownEndsAt! - before).toBeGreaterThanOrEqual(10_000);
    expect(screen.getByText("getReadyLabel")).toBeInTheDocument();
  });

  it("catches up on intervals that ran out while the screen was off, on schedule", async () => {
    const startedAt = Date.now() - 35_000; // 20 s work + 10 s rest + 5 s into work 2
    startAt(0, { segmentStartedAt: startedAt });
    render(<ExecutionMode />);

    await waitFor(() => expect(useExecutionStore.getState().currentSegmentIndex).toBe(2));
    const state = useExecutionStore.getState();
    expect(state.segmentStartedAt).toBe(startedAt + 30_000);
    expect(state.totalElapsedMs).toBe(30_000);
    expect(state.sectionElapsedMs).toEqual({ tabata: 30_000 });
  });

  it("counts AMRAP rounds with +1 and lets a round be removed", async () => {
    const amrap = [
      {
        ...tabataSegment(0, "AMRAP 12", "work"),
        section_id: "amrap",
        format: "amrap",
        duration_seconds: 720,
        total_rounds: null,
        round: null,
      } as TimerSegment,
    ];
    startAt(0, { segments: amrap });
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "addRoundLabel" }));
      fireEvent.click(screen.getByRole("button", { name: "addRoundLabel" }));
    });
    expect(useExecutionStore.getState().segmentCycleCounts["segment:0"]).toBe(2);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "removeRoundLabel" }));
    });
    expect(useExecutionStore.getState().segmentCycleCounts["segment:0"]).toBe(1);
    await waitFor(() => expect(updateExecutionProgress).toHaveBeenCalled());
  });

  it("undoes an accidental check-off", async () => {
    startAt(0);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /markStepDoneLabel/ }));
    });
    expect(useExecutionStore.getState().checkedExerciseIds).toEqual(["segment:0::burpee"]);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "editorUndo" }));
    });
    expect(useExecutionStore.getState().checkedExerciseIds).toEqual([]);
  });

  it("counts down the prescribed rest after a set of a straight-set exercise", async () => {
    const strength = [
      {
        ...tabataSegment(0, "Strength", "work"),
        section_id: "strength",
        format: "untimed",
        kind: "no_timer",
        duration_seconds: null,
        round: null,
        total_rounds: null,
        scoreable: false,
        score_config: null,
        exercises: [{ id: "squat", item_type: "exercise", name: "Squat", sets: 3, rest_seconds: 90 }],
      } as unknown as TimerSegment,
    ];
    startAt(0, { segments: strength });
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getAllByRole("button", { name: /markStepDoneLabel/ })[0]!);
    });

    const rest = screen.getByRole("timer", { name: "setRestLabel" });
    expect(rest).toHaveTextContent("1:30");

    fireEvent.click(screen.getByRole("button", { name: "skipRestLabel" }));
    expect(screen.queryByRole("timer", { name: "setRestLabel" })).not.toBeInTheDocument();
  });

  it("lets the clock be lengthened from the pause sheet", async () => {
    startAt(0);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    });
    fireEvent.click(await screen.findByRole("button", { name: "plusThirtySecondsLabel" }));

    const state = useExecutionStore.getState();
    expect(state.segments[0]!.duration_seconds).toBe(50);
    expect(state.durationAdjustments).toEqual({ "segment:0": 30 });
  });

  it("opens and closes the big-clock display", async () => {
    startAt(0);
    render(<ExecutionMode />);

    fireEvent.click(screen.getByRole("button", { name: "castModeLabel" }));
    const cast = screen.getByRole("dialog", { name: "castModeLabel" });
    expect(cast).toHaveTextContent("Work 1/2");

    fireEvent.click(cast);
    expect(screen.queryByRole("dialog", { name: "castModeLabel" })).not.toBeInTheDocument();
  });

  it("records skips, pauses and the finish review for execution KPIs", async () => {
    startAt(0);
    render(<ExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "nextbc98198" }));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    });
    await act(async () => {
      fireEvent.click(await screen.findByRole("button", { name: "endWorkoutLabel" }));
    });

    expect(useExecutionStore.getState().kpiCounters).toMatchObject({
      skips: 1,
      countdown_skips: 1,
      countdown_segments: 1,
      pauses: 1,
      finish_wizard_opens: 1,
    });
    await waitFor(() =>
      expect(updateExecutionProgress.mock.calls.at(-1)![2].kpi_counters).toMatchObject({ pauses: 1 }),
    );
  });
});
