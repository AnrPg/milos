import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type {
  KpiCounters,
  ExecutionProgressPayload,
  SectionScore,
  TimerBriefing,
  TimerSegment,
  WorkoutExecution,
} from "@/api/executions";
import type { JournalComment } from "@/api/journal-comments";
import { removeComment, sortComments, upsertComment } from "@/lib/journal-comments";
import { hasMarkChanges, type ProgressMarks, rebaseProgressMarks } from "@/lib/execution-rebase";
import { liveElapsedMs } from "@/lib/timer-engine";

export type ExecutionStatus = "idle" | "active" | "paused" | "completed";

/**
 * Elapsed-time model
 * ------------------
 * - `totalElapsedMs` / `sectionElapsedMs` hold *committed* time only: segments
 *   the athlete has left. The current segment is never included.
 * - `pausedElapsed` is time banked in the current segment by earlier pauses;
 *   while active, the running stretch is `now - segmentStartedAt`.
 * - Progress snapshots sent to the API carry committed + banked time
 *   (`buildProgressPayload`), and `hydrateFromExecution` subtracts the banked
 *   part again, so both sides derive each other exactly and a pause can never
 *   be counted twice.
 */
type ExecutionState = {
  executionId: string | null;
  lockVersion: number;
  workoutId: string | null;
  scaleSlug: string | null;
  /** The sequence with this execution's clock adjustments applied (what runs). */
  segments: TimerSegment[];
  /** The sequence as authored, before clock adjustments. */
  baseSegments: TimerSegment[];
  /** Οδηγίες read on the ready screen (ADR-140 §4). */
  briefing: TimerBriefing | null;
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
  /** Σχόλια on this execution (ADR-140 §1), oldest first. */
  comments: JournalComment[];
  /** Comments saved on this device the server has not acknowledged yet (outbox). */
  unsyncedCommentIds: string[];
  /** Local progress the server has not acknowledged yet. */
  pendingSync: boolean;
  /** Hand-made marks as the server last acknowledged them; the base for conflict rebases. */
  syncedMarks: ProgressMarks | null;
  /** Seconds added to (or removed from) segment clocks mid-workout, by segment key. */
  durationAdjustments: Record<string, number>;
  /** Execution KPIs only this device can observe (see `KpiCounters`). */
  kpiCounters: KpiCounters;
  /** When the athlete paused, for `paused_ms`. */
  kpiPausedAt: number | null;
  initExecution: (params: {
    executionId: string;
    lockVersion?: number;
    workoutId: string | null;
    scaleSlug: string | null;
    segments: TimerSegment[];
    briefing?: TimerBriefing | null;
    checkedExerciseIds?: string[];
    sectionScores?: SectionScore[];
    comments?: JournalComment[];
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
  setLockVersion: (lockVersion: number) => void;
  /** The server accepted `execution` while a newer local change waits: keep local state. */
  acknowledge: (execution: WorkoutExecution) => void;
  /**
   * Adopts a newer server version that conflicts with local progress, then
   * replays local check-offs, round counts and scores on top of it. Returns
   * true when local marks remain to be sent.
   */
  rebaseOnto: (execution: WorkoutExecution, segments?: TimerSegment[]) => boolean;
  setPendingSync: (pendingSync: boolean) => void;
  /** Elapsed time of the current segment at `now`. */
  currentElapsedMs: (now?: number) => number;
  /** Banks the running stretch; `maxElapsedMs` clamps it (a countdown cannot overrun). */
  pauseTimer: (pausedAt?: number, maxElapsedMs?: number | null) => void;
  startResumeCountdown: (endsAt: number) => void;
  resumeTimer: (startedAt?: number) => void;
  /**
   * Commits `elapsedMs` for the current segment and moves to `index`
   * (completing the execution when `index` is past the end).
   */
  moveToSegment: (index: number, params: { elapsedMs: number; startedAt: number }) => void;
  /** Commits several segments that ended on their own and lands on `index`. */
  applyCatchUp: (plan: {
    completed: { index: number; elapsedMs: number }[];
    index: number;
    segmentStartedAt: number;
  }) => void;
  /**
   * Lengthens or shortens a timed segment while the athlete trains (a coach
   * changing the plan mid-class). Never shortens below what already ran.
   */
  adjustSegmentDuration: (index: number, deltaSeconds: number) => void;
  /** Replaces the segment list, re-applying this execution's clock adjustments. */
  setSegments: (segments: TimerSegment[]) => void;
  setBriefing: (briefing: TimerBriefing | null) => void;
  /** Adds to a KPI counter. */
  countKpi: (key: Exclude<keyof KpiCounters, "first_started_at_ms">, amount?: number) => void;
  /** Records the athlete's pause (for pause count and paused time). */
  recordPauseKpi: (at?: number) => void;
  recordResumeKpi: (at?: number) => void;
  recordFirstStartKpi: (at?: number) => void;
  incrementSegmentCycle: (segmentKey: string) => void;
  decrementSegmentCycle: (segmentKey: string) => void;
  setCheckedExerciseIds: (exerciseIds: string[]) => void;
  upsertScore: (score: SectionScore) => void;
  /** A comment as saved locally (`unsynced`) or as the server answered. */
  upsertComment: (comment: JournalComment, options?: { unsynced?: boolean }) => void;
  removeComment: (id: string) => void;
  completeExecution: () => void;
  /** Committed totals plus the current segment's elapsed time at `now`. */
  completionTotals: (now?: number) => { totalElapsedMs: number; sectionElapsedMs: Record<string, number> };
  buildProgressPayload: () => ExecutionProgressPayload | null;
  reset: () => void;
};

const initialState = {
  executionId: null,
  lockVersion: 1,
  workoutId: null,
  scaleSlug: null,
  segments: [],
  briefing: null as TimerBriefing | null,
  baseSegments: [] as TimerSegment[],
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
  comments: [],
  unsyncedCommentIds: [],
  pendingSync: false,
  syncedMarks: null as ProgressMarks | null,
  durationAdjustments: {} as Record<string, number>,
  kpiCounters: {} as KpiCounters,
  kpiPausedAt: null as number | null,
};

const isCountdown = (segment: TimerSegment | undefined) => segment?.kind === "countdown";

const MIN_ADJUSTED_SECONDS = 5;
/** Matches the API's bound on a single segment's adjustment. */
const MAX_ADJUSTMENT_SECONDS = 3_600;

function isAdjustable(segment: TimerSegment | undefined): segment is TimerSegment & { duration_seconds: number } {
  return Boolean(
    segment &&
      typeof segment.duration_seconds === "number" &&
      (segment.kind === "countdown" || segment.kind === "countup"),
  );
}

export function applyDurationAdjustments(segments: TimerSegment[], adjustments: Record<string, number>) {
  if (Object.keys(adjustments).length === 0) return segments;
  return segments.map((segment) => {
    const delta = adjustments[segment.segment_key];
    if (!delta || !isAdjustable(segment)) return segment;
    return { ...segment, duration_seconds: Math.max(MIN_ADJUSTED_SECONDS, segment.duration_seconds + delta) };
  });
}

function marksOf(
  state: Pick<ExecutionState, "checkedExerciseIds" | "segmentCycleCounts" | "sectionScores" | "durationAdjustments">,
): ProgressMarks {
  return {
    checkedExerciseIds: state.checkedExerciseIds,
    segmentCycleCounts: state.segmentCycleCounts,
    sectionScores: state.sectionScores,
    durationAdjustments: state.durationAdjustments,
  };
}

/** The API stores adjustments enriched for coaches; the client works with plain deltas. */
export function adjustmentDeltas(stored: WorkoutExecution["duration_adjustments"]): Record<string, number> {
  const deltas: Record<string, number> = {};
  for (const [key, value] of Object.entries(stored ?? {})) {
    const delta = typeof value === "number" ? value : value?.delta_seconds;
    if (typeof delta === "number" && Number.isFinite(delta) && delta !== 0) deltas[key] = Math.round(delta);
  }
  return deltas;
}

function serverMarks(execution: WorkoutExecution): ProgressMarks {
  return {
    checkedExerciseIds: normalizeCheckedExerciseIds(execution.checked_exercise_ids),
    segmentCycleCounts: execution.segment_cycle_counts ?? {},
    sectionScores: execution.section_scores,
    durationAdjustments: adjustmentDeltas(execution.duration_adjustments),
  };
}

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

/** Time in between-section transitions/rests counts toward the workout, not a section. */
function sectionTimeKey(segment: TimerSegment | undefined) {
  return segment && !segment.between_sections ? segment.section_id : null;
}

function addElapsed(
  totals: { totalElapsedMs: number; sectionElapsedMs: Record<string, number> },
  segment: TimerSegment | undefined,
  elapsedMs: number,
) {
  const amount = Math.max(0, Math.round(elapsedMs));
  const key = sectionTimeKey(segment);
  return {
    totalElapsedMs: totals.totalElapsedMs + amount,
    sectionElapsedMs:
      key === null
        ? totals.sectionElapsedMs
        : { ...totals.sectionElapsedMs, [key]: (totals.sectionElapsedMs[key] ?? 0) + amount },
  };
}

/**
 * The server's comments are authoritative, except those this device saved
 * that have not reached it yet (they wait in the outbox).
 */
function hydratedComments(
  state: Pick<ExecutionState, "comments" | "unsyncedCommentIds">,
  execution: WorkoutExecution,
  sameExecution: boolean,
): Pick<ExecutionState, "comments" | "unsyncedCommentIds"> {
  if (execution.comments === undefined) {
    return sameExecution ? state : { comments: [], unsyncedCommentIds: [] };
  }
  const serverIds = new Set(execution.comments.map((comment) => comment.id));
  const unsynced = sameExecution
    ? state.comments.filter(
        (comment) => state.unsyncedCommentIds.includes(comment.id) && !serverIds.has(comment.id),
      )
    : [];
  return {
    comments: unsynced.reduce(upsertComment, sortComments(execution.comments)),
    unsyncedCommentIds: unsynced.map((comment) => comment.id),
  };
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
        briefing = null,
        checkedExerciseIds = [],
        sectionScores = [],
        comments = [],
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
          baseSegments: segments,
          briefing,
          checkedExerciseIds: normalizeCheckedExerciseIds(checkedExerciseIds),
          sectionScores,
          comments: sortComments(comments),
          currentSegmentIndex,
          status,
          segmentStartedAt: status === "active" ? segmentStartedAt : null,
          pausedElapsed,
          resumeCountdownEndsAt,
          totalElapsedMs,
          sectionElapsedMs,
          segmentCycleCounts,
          syncedMarks: {
            checkedExerciseIds: normalizeCheckedExerciseIds(checkedExerciseIds),
            segmentCycleCounts,
            sectionScores,
            durationAdjustments: {},
          },
        }),

      hydrateFromExecution: (execution, segments) =>
        set((state) => {
          const sameExecution = state.executionId === execution.id;
          // The server copy is authoritative; older APIs without the field keep local changes.
          const durationAdjustments =
            execution.duration_adjustments !== undefined
              ? adjustmentDeltas(execution.duration_adjustments)
              : sameExecution
                ? state.durationAdjustments
                : {};
          const baseSegments = segments ?? (state.baseSegments.length > 0 ? state.baseSegments : state.segments);
          const nextSegments = applyDurationAdjustments(baseSegments, durationAdjustments);
          const banked = Math.max(0, execution.paused_elapsed_ms ?? 0);
          const currentKey = sectionTimeKey(nextSegments[execution.current_segment_index]);
          const sectionElapsedMs = { ...(execution.section_elapsed_ms ?? {}) };
          if (currentKey !== null && sectionElapsedMs[currentKey] !== undefined) {
            sectionElapsedMs[currentKey] = Math.max(0, sectionElapsedMs[currentKey]! - banked);
          }

          return {
            executionId: execution.id,
            lockVersion: execution.lock_version,
            workoutId: execution.master_workout_id,
            scaleSlug: execution.scale_level_slug,
            segments: nextSegments,
            baseSegments,
            currentSegmentIndex: execution.current_segment_index,
            status: executionStatusFromApi(execution.status),
            segmentStartedAt:
              execution.status === "active"
                ? toTimestamp(execution.segment_started_at_utc)
                : null,
            pausedElapsed: banked,
            resumeCountdownEndsAt: toTimestamp(execution.resume_countdown_ends_at_utc),
            totalElapsedMs: Math.max(0, (execution.total_elapsed_ms ?? 0) - banked),
            sectionElapsedMs,
            segmentCycleCounts: execution.segment_cycle_counts ?? {},
            checkedExerciseIds: normalizeCheckedExerciseIds(execution.checked_exercise_ids),
            sectionScores: execution.section_scores,
            ...hydratedComments(state, execution, sameExecution),
            syncedMarks: serverMarks(execution),
            durationAdjustments,
            kpiCounters: sameExecution ? state.kpiCounters : {},
            kpiPausedAt: sameExecution ? state.kpiPausedAt : null,
          };
        }),

      setLockVersion: (lockVersion) => set({ lockVersion }),

      acknowledge: (execution) =>
        set({ lockVersion: execution.lock_version, syncedMarks: serverMarks(execution) }),

      rebaseOnto: (execution, segments) => {
        const before = get();
        const base = before.syncedMarks ?? serverMarks(execution);
        const local = marksOf(before);
        get().hydrateFromExecution(execution, segments);
        if (execution.status === "completed" || !hasMarkChanges(base, local)) return false;

        const server = serverMarks(execution);
        const rebased = rebaseProgressMarks(base, local, server);
        if (!hasMarkChanges(server, rebased)) return false;

        const adjustments = rebased.durationAdjustments ?? {};
        set((state) => ({
          ...rebased,
          durationAdjustments: adjustments,
          segments: applyDurationAdjustments(state.baseSegments, adjustments),
          syncedMarks: server,
          pendingSync: true,
        }));
        return true;
      },

      setPendingSync: (pendingSync) => set({ pendingSync }),

      currentElapsedMs: (now = Date.now()) => {
        const state = get();
        return liveElapsedMs({
          pausedElapsed: state.pausedElapsed,
          segmentStartedAt: state.segmentStartedAt,
          running: state.status === "active",
          now,
        });
      },

      pauseTimer: (pausedAt = Date.now(), maxElapsedMs = null) =>
        set((state) => {
          const elapsed = state.status === "active"
            ? liveElapsedMs({
                pausedElapsed: state.pausedElapsed,
                segmentStartedAt: state.segmentStartedAt,
                running: true,
                now: pausedAt,
              })
            : state.pausedElapsed;

          return {
            status: "paused",
            pausedElapsed: Math.round(maxElapsedMs === null ? elapsed : Math.min(elapsed, maxElapsedMs)),
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

      moveToSegment: (index, { elapsedMs, startedAt }) =>
        set((state) => {
          const committed = addElapsed(state, state.segments[state.currentSegmentIndex], elapsedMs);
          const kpiCounters =
            index > state.currentSegmentIndex && isCountdown(state.segments[state.currentSegmentIndex])
              ? { ...state.kpiCounters, countdown_segments: (state.kpiCounters.countdown_segments ?? 0) + 1 }
              : state.kpiCounters;

          if (index >= state.segments.length) {
            return {
              ...committed,
              kpiCounters,
              status: "completed" as ExecutionStatus,
              segmentStartedAt: null,
              pausedElapsed: 0,
              resumeCountdownEndsAt: null,
            };
          }

          if (index < 0) return state;

          return {
            ...committed,
            kpiCounters,
            currentSegmentIndex: index,
            segmentStartedAt: state.status === "active" ? startedAt : null,
            pausedElapsed: 0,
            resumeCountdownEndsAt: null,
          };
        }),

      applyCatchUp: ({ completed, index, segmentStartedAt }) =>
        set((state) => {
          let totals = { totalElapsedMs: state.totalElapsedMs, sectionElapsedMs: state.sectionElapsedMs };
          for (const step of completed) {
            totals = addElapsed(totals, state.segments[step.index], step.elapsedMs);
          }
          const countdowns = completed.filter((step) => isCountdown(state.segments[step.index])).length;

          return {
            ...totals,
            kpiCounters: countdowns
              ? { ...state.kpiCounters, countdown_segments: (state.kpiCounters.countdown_segments ?? 0) + countdowns }
              : state.kpiCounters,
            currentSegmentIndex: index,
            status: "active" as ExecutionStatus,
            segmentStartedAt,
            pausedElapsed: 0,
            resumeCountdownEndsAt: null,
          };
        }),

      adjustSegmentDuration: (index, deltaSeconds) =>
        set((state) => {
          const segment = state.segments[index];
          const authored = state.baseSegments[index] ?? segment;
          if (!isAdjustable(segment) || !isAdjustable(authored) || deltaSeconds === 0) return state;

          const ranSeconds =
            index === state.currentSegmentIndex ? Math.ceil(state.currentElapsedMs() / 1000) + 1 : 0;
          const nextDuration = Math.min(
            authored.duration_seconds + MAX_ADJUSTMENT_SECONDS,
            Math.max(
              MIN_ADJUSTED_SECONDS,
              ranSeconds,
              authored.duration_seconds - MAX_ADJUSTMENT_SECONDS,
              segment.duration_seconds + deltaSeconds,
            ),
          );
          if (nextDuration === segment.duration_seconds) return state;

          const durationAdjustments = { ...state.durationAdjustments };
          const delta = nextDuration - authored.duration_seconds;
          if (delta === 0) delete durationAdjustments[segment.segment_key];
          else durationAdjustments[segment.segment_key] = delta;

          return {
            durationAdjustments,
            segments: applyDurationAdjustments(
              state.baseSegments.length > 0 ? state.baseSegments : state.segments,
              durationAdjustments,
            ),
          };
        }),

      setSegments: (segments) =>
        set((state) => ({
          baseSegments: segments,
          segments: applyDurationAdjustments(segments, state.durationAdjustments),
        })),

      countKpi: (key, amount = 1) =>
        set((state) => ({
          kpiCounters: { ...state.kpiCounters, [key]: Math.max(0, Math.round((state.kpiCounters[key] ?? 0) + amount)) },
        })),

      recordPauseKpi: (at = Date.now()) =>
        set((state) => ({
          kpiCounters: { ...state.kpiCounters, pauses: (state.kpiCounters.pauses ?? 0) + 1 },
          kpiPausedAt: at,
        })),

      recordResumeKpi: (at = Date.now()) =>
        set((state) =>
          state.kpiPausedAt === null
            ? state
            : {
                kpiCounters: {
                  ...state.kpiCounters,
                  paused_ms: (state.kpiCounters.paused_ms ?? 0) + Math.max(0, at - state.kpiPausedAt),
                },
                kpiPausedAt: null,
              },
        ),

      recordFirstStartKpi: (at = Date.now()) =>
        set((state) =>
          state.kpiCounters.first_started_at_ms
            ? state
            : { kpiCounters: { ...state.kpiCounters, first_started_at_ms: Math.round(at) } },
        ),

      incrementSegmentCycle: (segmentKey) =>
        set((state) => ({
          segmentCycleCounts: {
            ...state.segmentCycleCounts,
            [segmentKey]: (state.segmentCycleCounts[segmentKey] ?? 0) + 1,
          },
        })),

      decrementSegmentCycle: (segmentKey) =>
        set((state) => ({
          segmentCycleCounts: {
            ...state.segmentCycleCounts,
            [segmentKey]: Math.max(0, (state.segmentCycleCounts[segmentKey] ?? 0) - 1),
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

      upsertComment: (comment, options) =>
        set((state) => ({
          comments: upsertComment(state.comments, comment),
          unsyncedCommentIds: options?.unsynced
            ? [...new Set([...state.unsyncedCommentIds, comment.id])]
            : state.unsyncedCommentIds.filter((id) => id !== comment.id),
        })),

      removeComment: (id) =>
        set((state) => ({
          comments: removeComment(state.comments, id),
          unsyncedCommentIds: state.unsyncedCommentIds.filter((candidate) => candidate !== id),
        })),

      completeExecution: () =>
        set({
          status: "completed",
          segmentStartedAt: null,
          pausedElapsed: 0,
          resumeCountdownEndsAt: null,
          pendingSync: false,
        }),

      completionTotals: (now = Date.now()) => {
        const state = get();
        return addElapsed(state, state.segments[state.currentSegmentIndex], state.currentElapsedMs(now));
      },

      buildProgressPayload: () => {
        const state = get();
        if (!state.executionId) return null;

        const snapshot = addElapsed(state, state.segments[state.currentSegmentIndex], state.pausedElapsed);

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
          paused_elapsed_ms: Math.round(state.pausedElapsed),
          total_elapsed_ms: snapshot.totalElapsedMs,
          section_elapsed_ms: snapshot.sectionElapsedMs,
          segment_cycle_counts: state.segmentCycleCounts,
          section_scores: state.sectionScores,
          resume_countdown_ends_at_utc: state.resumeCountdownEndsAt
            ? new Date(state.resumeCountdownEndsAt).toISOString()
            : null,
          kpi_counters: state.kpiCounters,
          duration_adjustments: state.durationAdjustments,
        };
      },

      setBriefing: (briefing) => set({ briefing }),

      reset: () => set(initialState),
    }),
    {
      name: "milos-execution-store",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        executionId: state.executionId,
        lockVersion: state.lockVersion,
        workoutId: state.workoutId,
        briefing: state.briefing,
        scaleSlug: state.scaleSlug,
        segments: state.segments,
        baseSegments: state.baseSegments,
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
        comments: state.comments,
        unsyncedCommentIds: state.unsyncedCommentIds,
        pendingSync: state.pendingSync,
        syncedMarks: state.syncedMarks,
        durationAdjustments: state.durationAdjustments,
        kpiCounters: state.kpiCounters,
        kpiPausedAt: state.kpiPausedAt,
      }),
    },
  ),
);
