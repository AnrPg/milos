import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type {
  ExerciseNote,
  ExecutionProgressPayload,
  SectionScore,
  TimerSegment,
  WorkoutExecution,
} from "@/api/executions";

export type ExecutionStatus = "idle" | "active" | "paused" | "completed";

type ExecutionState = {
  executionId: string | null;
  lockVersion: number;
  workoutId: string | null;
  scaleSlug: string | null;
  segments: TimerSegment[];
  currentSegmentIndex: number;
  status: ExecutionStatus;
  segmentStartedAt: number | null;
  pausedElapsed: number;
  resumeCountdownEndsAt: number | null;
  totalElapsedMs: number;
  sectionElapsedMs: Record<string, number>;
  segmentCycleCounts: Record<string, number>;
  checkedExerciseIds: string[];
  sectionScores: SectionScore[];
  exerciseNotes: ExerciseNote[];
  initExecution: (params: {
    executionId: string;
    lockVersion?: number;
    workoutId: string | null;
    scaleSlug: string | null;
    segments: TimerSegment[];
    checkedExerciseIds?: string[];
    sectionScores?: SectionScore[];
    exerciseNotes?: ExerciseNote[];
    currentSegmentIndex?: number;
    status?: ExecutionStatus;
    segmentStartedAt?: number | null;
    pausedElapsed?: number;
    resumeCountdownEndsAt?: number | null;
    totalElapsedMs?: number;
    sectionElapsedMs?: Record<string, number>;
    segmentCycleCounts?: Record<string, number>;
  }) => void;
  hydrateFromExecution: (execution: WorkoutExecution, segments?: TimerSegment[]) => void;
  startTimer: (startedAt?: number) => void;
  pauseTimer: (pausedAt?: number) => void;
  startResumeCountdown: (endsAt: number) => void;
  resumeTimer: (startedAt?: number) => void;
  advanceSegment: (startedAt?: number) => void;
  jumpToSegment: (index: number, startedAt?: number) => void;
  commitSegmentElapsed: (sectionId: string, elapsedMs: number) => void;
  incrementSegmentCycle: (segmentKey: string) => void;
  setCheckedExerciseIds: (exerciseIds: string[]) => void;
  upsertScore: (score: SectionScore) => void;
  upsertNote: (note: ExerciseNote) => void;
  replaceNotes: (notes: ExerciseNote[]) => void;
  completeExecution: () => void;
  buildProgressPayload: (snapshot?: {
    currentSegment: TimerSegment | null;
    currentElapsedMs: number;
  }) => ExecutionProgressPayload | null;
  reset: () => void;
};

const initialState = {
  executionId: null,
  lockVersion: 1,
  workoutId: null,
  scaleSlug: null,
  segments: [],
  currentSegmentIndex: 0,
  status: "idle" as ExecutionStatus,
  segmentStartedAt: null,
  pausedElapsed: 0,
  resumeCountdownEndsAt: null,
  totalElapsedMs: 0,
  sectionElapsedMs: {},
  segmentCycleCounts: {},
  checkedExerciseIds: [],
  sectionScores: [],
  exerciseNotes: [],
};

function executionStatusFromApi(status: WorkoutExecution["status"]): ExecutionStatus {
  if (status === "active" || status === "paused" || status === "completed") {
    return status;
  }

  return "idle";
}

function toTimestamp(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function normalizeCheckedExerciseIds(exerciseIds: string[]) {
  return Array.from(new Set(exerciseIds));
}

export const useExecutionStore = create<ExecutionState>()(
  persist(
    (set, get) => ({
      ...initialState,

      initExecution: ({
        executionId,
        lockVersion = 1,
        workoutId,
        scaleSlug,
        segments,
        checkedExerciseIds = [],
        sectionScores = [],
        exerciseNotes = [],
        currentSegmentIndex = 0,
        status = "active",
        segmentStartedAt = Date.now(),
        pausedElapsed = 0,
        resumeCountdownEndsAt = null,
        totalElapsedMs = 0,
        sectionElapsedMs = {},
        segmentCycleCounts = {},
      }) =>
        set({
          ...initialState,
          executionId,
          lockVersion,
          workoutId,
          scaleSlug,
          segments,
          checkedExerciseIds: normalizeCheckedExerciseIds(checkedExerciseIds),
          sectionScores,
          exerciseNotes,
          currentSegmentIndex,
          status,
          segmentStartedAt: status === "active" ? segmentStartedAt : null,
          pausedElapsed,
          resumeCountdownEndsAt,
          totalElapsedMs,
          sectionElapsedMs,
          segmentCycleCounts,
        }),

      hydrateFromExecution: (execution, segments) =>
        set((state) => ({
          executionId: execution.id,
          lockVersion: execution.lock_version,
          workoutId: execution.master_workout_id,
          scaleSlug: execution.scale_level_slug,
          segments: segments ?? state.segments,
          currentSegmentIndex: execution.current_segment_index,
          status: executionStatusFromApi(execution.status),
          segmentStartedAt:
            execution.status === "active"
              ? toTimestamp(execution.segment_started_at_utc)
              : null,
          pausedElapsed: execution.paused_elapsed_ms,
          resumeCountdownEndsAt: toTimestamp(execution.resume_countdown_ends_at_utc),
          totalElapsedMs: execution.total_elapsed_ms,
          sectionElapsedMs: execution.section_elapsed_ms,
          segmentCycleCounts: execution.segment_cycle_counts,
          checkedExerciseIds: normalizeCheckedExerciseIds(execution.checked_exercise_ids),
          sectionScores: execution.section_scores,
          exerciseNotes: execution.exercise_notes,
        })),

      startTimer: (startedAt = Date.now()) =>
        set({
          status: "active",
          segmentStartedAt: startedAt,
          pausedElapsed: 0,
          resumeCountdownEndsAt: null,
        }),

      pauseTimer: (pausedAt = Date.now()) =>
        set((state) => {
          const elapsed = state.segmentStartedAt
            ? state.pausedElapsed + (pausedAt - state.segmentStartedAt)
            : state.pausedElapsed;

          return {
            status: "paused",
            pausedElapsed: elapsed,
            segmentStartedAt: null,
            resumeCountdownEndsAt: null,
          };
        }),

      startResumeCountdown: (endsAt) =>
        set({
          status: "paused",
          segmentStartedAt: null,
          resumeCountdownEndsAt: endsAt,
        }),

      resumeTimer: (startedAt = Date.now()) =>
        set({
          status: "active",
          segmentStartedAt: startedAt,
          resumeCountdownEndsAt: null,
        }),

      advanceSegment: (startedAt = Date.now()) =>
        set((state) => {
          const next = state.currentSegmentIndex + 1;

          if (next >= state.segments.length) {
            return {
              status: "completed" as ExecutionStatus,
              currentSegmentIndex: state.currentSegmentIndex,
              segmentStartedAt: null,
              pausedElapsed: 0,
              resumeCountdownEndsAt: null,
            };
          }

          return {
            currentSegmentIndex: next,
            status: "active" as ExecutionStatus,
            segmentStartedAt: startedAt,
            pausedElapsed: 0,
            resumeCountdownEndsAt: null,
          };
        }),

      jumpToSegment: (index, startedAt = Date.now()) =>
        set((state) => {
          if (index < 0 || index >= state.segments.length) return state;

          return {
            currentSegmentIndex: index,
            segmentStartedAt: state.status === "active" ? startedAt : null,
            pausedElapsed: 0,
            resumeCountdownEndsAt: null,
          };
        }),

      commitSegmentElapsed: (sectionId, elapsedMs) =>
        set((state) => ({
          totalElapsedMs: state.totalElapsedMs + Math.max(0, elapsedMs),
          sectionElapsedMs: {
            ...state.sectionElapsedMs,
            [sectionId]: (state.sectionElapsedMs[sectionId] ?? 0) + Math.max(0, elapsedMs),
          },
        })),

      incrementSegmentCycle: (segmentKey) =>
        set((state) => ({
          segmentCycleCounts: {
            ...state.segmentCycleCounts,
            [segmentKey]: (state.segmentCycleCounts[segmentKey] ?? 0) + 1,
          },
        })),

      setCheckedExerciseIds: (exerciseIds) =>
        set({ checkedExerciseIds: normalizeCheckedExerciseIds(exerciseIds) }),

      upsertScore: (score) =>
        set((state) => {
          const existing = state.sectionScores.findIndex(
            (candidate) => candidate.section_id === score.section_id,
          );
          const updated =
            existing >= 0
              ? state.sectionScores.map((candidate, index) =>
                  index === existing ? score : candidate,
                )
              : [...state.sectionScores, score];

          return { sectionScores: updated };
        }),

      upsertNote: (note) =>
        set((state) => {
          const existing = state.exerciseNotes.findIndex((candidate) => {
            if (note.id && candidate.id) {
              return candidate.id === note.id;
            }

            return (
              candidate.exercise_id === note.exercise_id &&
              candidate.selected_text === note.selected_text &&
              candidate.selection_start === note.selection_start &&
              candidate.selection_end === note.selection_end
            );
          });

          const updated =
            existing >= 0
              ? state.exerciseNotes.map((candidate, index) =>
                  index === existing ? note : candidate,
                )
              : [...state.exerciseNotes, note];

          return { exerciseNotes: updated };
        }),

      replaceNotes: (notes) => set({ exerciseNotes: notes }),

      completeExecution: () =>
        set({
          status: "completed",
          segmentStartedAt: null,
          pausedElapsed: 0,
          resumeCountdownEndsAt: null,
        }),

      buildProgressPayload: (snapshot) => {
        const state = get();
        const currentSegment = snapshot?.currentSegment ?? null;
        const currentElapsedMs = Math.max(0, snapshot?.currentElapsedMs ?? 0);
        const effectiveSectionElapsedMs = { ...state.sectionElapsedMs };

        if (currentSegment) {
          effectiveSectionElapsedMs[currentSegment.section_id] =
            (effectiveSectionElapsedMs[currentSegment.section_id] ?? 0) + currentElapsedMs;
        }

        if (!state.executionId) {
          return null;
        }

        return {
          expected_version: state.lockVersion,
          operation_id: crypto.randomUUID(),
          checked_exercise_ids: state.checkedExerciseIds,
          current_segment_index: state.currentSegmentIndex,
          status: state.status === "paused" ? "paused" : "active",
          segment_started_at_utc:
            state.status === "active" && state.segmentStartedAt
              ? new Date(state.segmentStartedAt).toISOString()
              : null,
          paused_elapsed_ms: state.pausedElapsed,
          total_elapsed_ms: state.totalElapsedMs + currentElapsedMs,
          section_elapsed_ms: effectiveSectionElapsedMs,
          segment_cycle_counts: state.segmentCycleCounts,
          section_scores: state.sectionScores,
          resume_countdown_ends_at_utc: state.resumeCountdownEndsAt
            ? new Date(state.resumeCountdownEndsAt).toISOString()
            : null,
        };
      },

      reset: () => set(initialState),
    }),
    {
      name: "milos-execution-store",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        executionId: state.executionId,
        lockVersion: state.lockVersion,
        workoutId: state.workoutId,
        scaleSlug: state.scaleSlug,
        segments: state.segments,
        currentSegmentIndex: state.currentSegmentIndex,
        status: state.status,
        segmentStartedAt: state.segmentStartedAt,
        pausedElapsed: state.pausedElapsed,
        resumeCountdownEndsAt: state.resumeCountdownEndsAt,
        totalElapsedMs: state.totalElapsedMs,
        sectionElapsedMs: state.sectionElapsedMs,
        segmentCycleCounts: state.segmentCycleCounts,
        checkedExerciseIds: state.checkedExerciseIds,
        sectionScores: state.sectionScores,
        exerciseNotes: state.exerciseNotes,
      }),
    },
  ),
);
