"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { useCallback, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import {
  addExecutionModifications,
  completeExecution as completeExecutionRequest,
  type ExerciseModification,
  type ExerciseNote,
  type SectionScore,
  type TimerSegment,
  type WorkoutExecution,
} from "@/api/executions";
import { useSession } from "@/components/session-provider";
import { LocalizedScore } from "@/components/localized-score";
import { useExecutionSync, type SyncProblem } from "@/hooks/useExecutionSync";
import { useMediaSession } from "@/hooks/useMediaSession";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useWorkoutTimer } from "@/hooks/useWorkoutTimer";
import { subscribeToTopic } from "@/lib/realtime";
import { segmentLabel } from "@/lib/segment-label";
import { planCatchUp, segmentLimitMs } from "@/lib/timer-engine";
import {
  CUE_MODES,
  type CueMode,
  type CueSnapshot,
  nextCue,
  playCue,
  primeCueAudio,
  readCueMode,
  storeCueMode,
} from "@/lib/timer-cues";
import { useExecutionStore } from "@/stores/execution";
import { getFormatLabels, type SectionFormat } from "@/types/workout";

import { FinishWizard } from "./FinishWizard";
import { ModificationModal } from "./ModificationModal";
import {
  buildSegmentStepIds,
  computeMeasuredScore,
  isLastSegmentOfSection,
  isRepeatableSegment,
  roundTarget as segmentRoundTarget,
  shouldAutoAdvanceOnChecklistComplete,
  setRestSeconds,
  stepsForWindow,
  targetRepsForRound,
} from "./progress";
import { ReadyScreen } from "./ReadyScreen";
import { ScoreModal } from "./ScoreModal";
import { CastView } from "./CastView";
import { displaySeconds, formatClock, PHASE_COLORS, type TimerPhase, TimerDisplay } from "./TimerDisplay";
import { type ChecklistStep, toChecklistSteps, WorkoutChecklist } from "./WorkoutChecklist";

const GET_READY_MS = 10_000;
const RESUME_COUNTDOWN_MS = 3_000;
const UNDO_VISIBLE_MS = 5_000;

function mergeSectionScore(scores: SectionScore[], nextScore: SectionScore) {
  const existing = scores.findIndex((score) => score.section_id === nextScore.section_id);

  if (existing >= 0) {
    return scores.map((score, index) => (index === existing ? nextScore : score));
  }

  return [...scores, nextScore];
}

/** Older executions stored plain exercise ids; expand them to this segment's step ids. */
function normalizeCheckedExerciseIds(checkedExerciseIds: string[], segmentSteps: ChecklistStep[]) {
  const next = checkedExerciseIds.filter((id) => {
    if (!segmentSteps.some((step) => step.exerciseId === id)) {
      return true;
    }

    return segmentSteps.some((step) => step.stepId === id);
  });

  for (const exerciseId of new Set(segmentSteps.map((step) => step.exerciseId))) {
    if (checkedExerciseIds.includes(exerciseId)) {
      next.push(...segmentSteps.filter((step) => step.exerciseId === exerciseId).map((step) => step.stepId));
    }
  }

  return Array.from(new Set(next));
}

function segmentPhase(segment: TimerSegment): TimerPhase {
  if (segment.phase) return segment.phase;
  return segment.format === "rest" || (segment.kind === "countdown" && segment.exercises.length === 0)
    ? "rest"
    : "work";
}

function isExecutionPayload(value: unknown): value is { execution: WorkoutExecution } {
  return (
    typeof value === "object" &&
    value !== null &&
    "execution" in value &&
    typeof value.execution === "object" &&
    value.execution !== null
  );
}

const CUE_MODE_LABELS: Record<CueMode, string> = {
  sound: "cueModeSoundLabel",
  vibrate: "cueModeVibrateLabel",
  off: "cueModeOffLabel",
};

function PauseIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <rect x="6" y="4" width="4" height="16" rx="1" />
      <rect x="14" y="4" width="4" height="16" rx="1" />
    </svg>
  );
}

function CastIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 7V5h16v14h-6" />
      <path d="M4 11a8 8 0 0 1 8 8" />
      <path d="M4 15a4 4 0 0 1 4 4" />
      <path d="M4 19h.01" />
    </svg>
  );
}

function CueModeIcon({ mode }: { mode: CueMode }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {mode === "vibrate" ? (
        <>
          <rect x="8" y="3" width="8" height="18" rx="2" />
          <path d="M4 8v8M20 8v8" />
        </>
      ) : (
        <>
          <path d="M11 5 6 9H3v6h3l5 4z" />
          {mode === "sound" ? <path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13" /> : <path d="m16 9 6 6M22 9l-6 6" />}
        </>
      )}
    </svg>
  );
}

type UndoState = {
  message: string;
  segmentIndex: number;
  checkedExerciseIds: string[];
  segmentCycleCounts: Record<string, number>;
};

export function ExecutionMode() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { tokens } = useSession();
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);

  const {
    executionId,
    lockVersion,
    segments,
    currentSegmentIndex,
    status,
    segmentStartedAt,
    pausedElapsed,
    resumeCountdownEndsAt,
    totalElapsedMs,
    sectionElapsedMs,
    segmentCycleCounts,
    checkedExerciseIds,
    sectionScores,
    pendingSync,
    pauseTimer,
    startResumeCountdown,
    resumeTimer,
    moveToSegment,
    applyCatchUp,
    incrementSegmentCycle,
    decrementSegmentCycle,
    adjustSegmentDuration,
    setCheckedExerciseIds,
    upsertScore,
    upsertNote,
    hydrateFromExecution,
    completeExecution,
    reset,
  } = useExecutionStore();

  const [showScoreModal, setShowScoreModal] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [countdownNow, setCountdownNow] = useState(() => Date.now());
  const [inExecutionModifications, setInExecutionModifications] = useState<ExerciseModification[]>([]);
  const [modifyTarget, setModifyTarget] = useState<ChecklistStep | null>(null);
  const [pendingFinish, setPendingFinish] = useState<{ scores: SectionScore[] } | null>(null);
  const [undo, setUndo] = useState<UndoState | null>(null);
  const [cueMode, setCueMode] = useState<CueMode>(() => readCueMode());
  /** Rest between straight sets, counted down on the device after a set check-off. */
  const [setRest, setSetRest] = useState<{ endsAt: number; total: number; segmentIndex: number } | null>(null);
  const [castMode, setCastMode] = useState(false);
  const exitCastMode = useCallback(() => setCastMode(false), []);

  const onSyncProblem = useCallback(
    (problem: SyncProblem) =>
      setFeedback(
        problem === "conflict"
          ? i18n("progressConflictLabel")
          : problem === "merged"
            ? i18n("progressMergedLabel")
            : i18n("progressSavedOfflineLabel"),
      ),
    [i18n],
  );
  const { sync, isSyncing } = useExecutionSync(tokens?.access_token, executionId, onSyncProblem);

  const currentSegment = segments[currentSegmentIndex] ?? null;
  const isLastSegment = currentSegmentIndex === segments.length - 1;
  // A freshly started execution waits on the ready screen; the clock starts
  // after the get-ready countdown, not when the API created the record.
  const awaitingStart =
    status === "active" &&
    lockVersion <= 1 &&
    currentSegmentIndex === 0 &&
    totalElapsedMs === 0 &&
    pausedElapsed === 0 &&
    checkedExerciseIds.length === 0 &&
    !pendingSync;
  const isTimerRunning = status === "active" && !awaitingStart && !showScoreModal;
  // Interval formats split one section into many segments; only the section's
  // final segment asks for a score so Tabata/EMOM never interrupt every interval.
  const promptsForScore =
    Boolean(currentSegment?.scoreable) && isLastSegmentOfSection(segments, currentSegmentIndex);

  const timer = useWorkoutTimer(currentSegment, isTimerRunning, pausedElapsed, segmentStartedAt);
  const intervalWindow = timer.clock?.window ?? null;
  const phase = currentSegment ? segmentPhase(currentSegment) : "work";

  const segmentSteps = useMemo(
    () => (currentSegment ? toChecklistSteps(stepsForWindow(currentSegment, intervalWindow?.index ?? null)) : []),
    [currentSegment, intervalWindow?.index],
  );
  const repeatable = currentSegment ? isRepeatableSegment(currentSegment) : false;
  const roundsCompleted = currentSegment && repeatable ? segmentCycleCounts[currentSegment.segment_key] ?? 0 : null;
  const roundTarget = currentSegment ? segmentRoundTarget(currentSegment) : null;
  const targetReps =
    currentSegment?.format === "death_by" && intervalWindow
      ? targetRepsForRound(currentSegment, intervalWindow.index)
      : null;
  const nextSegment = segments[currentSegmentIndex + 1] ?? null;

  const resumeCountdown = useMemo(() => {
    if (!resumeCountdownEndsAt) return null;
    return Math.max(0, Math.ceil((resumeCountdownEndsAt - countdownNow) / 1000));
  }, [countdownNow, resumeCountdownEndsAt]);
  const isGetReadyCountdown = resumeCountdown !== null && currentSegmentIndex === 0 && totalElapsedMs === 0 && pausedElapsed === 0;

  /** Applies a change locally right away, then persists it in the background. */
  function commit(mutate: () => void) {
    mutate();
    void sync();
  }

  const limitOf = (segment: TimerSegment | null) => (segment ? segmentLimitMs(segment) : null);
  const canAutoAdvance = (index: number) =>
    index < segments.length - 1 &&
    !(segments[index]?.scoreable && isLastSegmentOfSection(segments, index));

  function goToSegment(index: number) {
    const now = Date.now();
    const store = useExecutionStore.getState();
    const limit = limitOf(currentSegment);
    const elapsed = store.currentElapsedMs(now);
    setUndo(null);
    commit(() =>
      moveToSegment(index, { elapsedMs: limit === null ? elapsed : Math.min(elapsed, limit), startedAt: now }),
    );
  }

  function pauseNow() {
    if (useExecutionStore.getState().status !== "active") return;
    commit(() => pauseTimer(Date.now(), limitOf(currentSegment)));
  }

  /** The athlete paused (as opposed to a pause the app takes, e.g. for the review). */
  function userPause() {
    if (useExecutionStore.getState().status !== "active") return;
    useExecutionStore.getState().recordPauseKpi();
    pauseNow();
  }

  /** The athlete ended the segment before its clock ran out. */
  function skipSegment() {
    const limit = limitOf(currentSegment);
    if (currentSegment && limit !== null && !timer.isExpired) {
      const store = useExecutionStore.getState();
      store.countKpi("skips");
      if (currentSegment.kind === "countdown") store.countKpi("countdown_skips");
    }
    endCurrentSegment();
  }

  function openScoreModal() {
    pauseNow();
    setShowScoreModal(true);
  }

  function handleFinish(finalSectionScores: SectionScore[] = sectionScores) {
    if (!tokens?.access_token || !executionId) return;

    // Freeze the clock while the athlete reviews, so backing out of the review
    // returns to a paused workout instead of one that kept running underneath.
    useExecutionStore.getState().countKpi("finish_wizard_opens");
    pauseNow();
    setShowScoreModal(false);
    setPendingFinish({ scores: finalSectionScores });
  }

  /** Ends the current segment: score prompt, finish, or the next segment. */
  function endCurrentSegment() {
    if (promptsForScore) openScoreModal();
    else if (isLastSegment) handleFinish();
    else goToSegment(currentSegmentIndex + 1);
  }

  async function confirmPendingFinish(editedScores: SectionScore[], modifications: ExerciseModification[]) {
    if (!tokens?.access_token || !executionId) return;
    setIsSaving(true);
    setFeedback(null);

    try {
      if (modifications.length > 0) {
        const execution = await addExecutionModifications(tokens.access_token, executionId, modifications);
        hydrateFromExecution(execution);
      }

      // Let queued progress land first so it cannot arrive after completion.
      await sync();
      const store = useExecutionStore.getState();
      const totals = store.completionTotals(Date.now());
      const execution = await completeExecutionRequest(tokens.access_token, executionId, {
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        checked_exercise_ids: store.checkedExerciseIds,
        section_scores: editedScores,
        exercise_notes: store.exerciseNotes,
        total_elapsed_ms: totals.totalElapsedMs,
        section_elapsed_ms: totals.sectionElapsedMs,
        segment_cycle_counts: store.segmentCycleCounts,
        kpi_counters: store.kpiCounters,
      });
      hydrateFromExecution(execution);
      completeExecution();
      setPendingFinish(null);
    } catch {
      setFeedback(i18n("workoutCompletionCouldNotBeSavedTryAgaindce610c"));
    } finally {
      setIsSaving(false);
    }
  }

  // ── Timer-driven transitions ────────────────────────────────────────────────

  const handleExpiredSegment = useEffectEvent(() => {
    if (promptsForScore || isLastSegment) {
      endCurrentSegment();
      return;
    }

    // Start the next segment when this one ended, not when the app noticed —
    // and skip through every segment that ran out while the phone was locked.
    const now = Date.now();
    const store = useExecutionStore.getState();
    const plan = planCatchUp(segments, currentSegmentIndex, now - store.currentElapsedMs(now), now, canAutoAdvance);
    if (plan.completed.length === 0) return;

    setUndo(null);
    commit(() => applyCatchUp(plan));
  });

  useEffect(() => {
    if (!timer.isExpired || !isTimerRunning) return;
    const timeoutId = window.setTimeout(() => handleExpiredSegment(), 0);
    return () => window.clearTimeout(timeoutId);
  }, [timer.isExpired, isTimerRunning, currentSegmentIndex]);

  // A new interval window starts with a clean checklist.
  const windowIndex = intervalWindow?.index ?? null;
  useEffect(() => {
    if (windowIndex === null || !currentSegment) return;
    const stepIds = buildSegmentStepIds(currentSegment);
    const store = useExecutionStore.getState();
    if (!store.checkedExerciseIds.some((id) => stepIds.includes(id))) return;
    store.setCheckedExerciseIds(store.checkedExerciseIds.filter((id) => !stepIds.includes(id)));
    void sync();
  }, [windowIndex, currentSegment, sync]);

  // A set rest belongs to the segment it started in, and ends on its own.
  const activeSetRest = setRest && setRest.segmentIndex === currentSegmentIndex ? setRest : null;
  const setRestRemaining = activeSetRest
    ? Math.max(0, Math.ceil((activeSetRest.endsAt - countdownNow) / 1000))
    : null;
  const showSetRest = setRestRemaining !== null && setRestRemaining > 0;

  const countdownRunning = resumeCountdownEndsAt !== null || showSetRest;
  useEffect(() => {
    if (!countdownRunning) return;
    const intervalId = setInterval(() => setCountdownNow(Date.now()), 250);
    return () => clearInterval(intervalId);
  }, [countdownRunning]);

  useEffect(() => {
    if (setRestRemaining === null) return;
    if (setRestRemaining === 0) playCue("work", cueMode);
    else if (setRestRemaining <= 3) playCue("tick", cueMode);
  }, [cueMode, setRestRemaining]);

  const resumeAfterCountdown = useEffectEvent(() => {
    // Resume at the scheduled moment, even if the countdown finished in the background.
    if (resumeCountdownEndsAt) commit(() => resumeTimer(resumeCountdownEndsAt));
  });

  useEffect(() => {
    if (!resumeCountdownEndsAt || countdownNow < resumeCountdownEndsAt) return;
    resumeAfterCountdown();
  }, [countdownNow, resumeCountdownEndsAt]);

  // ── Cues, wake lock, realtime ───────────────────────────────────────────────

  useScreenWakeLock(status !== "completed");

  const previousCueRef = useRef<CueSnapshot | null>(null);
  const cueKey = currentSegment ? `${currentSegment.segment_key}#${windowIndex ?? 0}` : null;
  const cuePhase = phase === "work" ? "work" : "rest";

  useEffect(() => {
    const snapshot: CueSnapshot = {
      segmentKey: cueKey,
      running: isTimerRunning,
      remaining: timer.remaining,
      phase: cuePhase,
    };
    const cue = nextCue(previousCueRef.current, snapshot);
    previousCueRef.current = snapshot;
    if (cue) playCue(cue, cueMode);
  }, [cueKey, cueMode, cuePhase, isTimerRunning, timer.remaining]);

  useEffect(() => {
    if (resumeCountdown !== null && resumeCountdown > 0 && resumeCountdown <= 3) playCue("tick", cueMode);
  }, [cueMode, resumeCountdown]);

  const previousStatusRef = useRef(status);
  useEffect(() => {
    if (status === "completed" && previousStatusRef.current !== "completed") playCue("finish", cueMode);
    previousStatusRef.current = status;
  }, [cueMode, status]);

  function cycleCueMode() {
    primeCueAudio();
    const next = CUE_MODES[(CUE_MODES.indexOf(cueMode) + 1) % CUE_MODES.length]!;
    storeCueMode(next);
    setCueMode(next);
    if (next !== "off") playCue("tick", next);
  }

  useEffect(() => {
    if (!tokens?.access_token || !executionId) return;

    return subscribeToTopic(tokens.access_token, "execution:" + executionId, {
      "execution:progress_updated": (payload) => {
        // Ignore echoes of our own writes and anything older than local state.
        if (!isExecutionPayload(payload) || isSyncing()) return;
        if (payload.execution.lock_version <= useExecutionStore.getState().lockVersion) return;
        hydrateFromExecution(payload.execution);
      },
      "execution:note_submitted": (payload) => {
        if (
          typeof payload === "object" &&
          payload !== null &&
          "note" in payload &&
          payload.note &&
          typeof payload.note === "object"
        ) {
          upsertNote(payload.note as ExerciseNote);
        }
      },
      "execution:completed": (payload) => {
        if (isExecutionPayload(payload)) {
          hydrateFromExecution(payload.execution);
        }
        completeExecution();
      },
    });
  }, [completeExecution, executionId, hydrateFromExecution, isSyncing, tokens?.access_token, upsertNote]);

  useEffect(() => {
    if (!undo) return;
    const timeoutId = setTimeout(() => setUndo(null), UNDO_VISIBLE_MS);
    return () => clearTimeout(timeoutId);
  }, [undo]);

  // ── Athlete actions ─────────────────────────────────────────────────────────

  function handleStart() {
    primeCueAudio();
    useExecutionStore.getState().recordFirstStartKpi();
    commit(() => {
      useExecutionStore.setState({ pausedElapsed: 0 });
      startResumeCountdown(Date.now() + GET_READY_MS);
    });
  }

  function handleResume() {
    primeCueAudio();
    useExecutionStore.getState().recordResumeKpi();
    commit(() => startResumeCountdown(Date.now() + RESUME_COUNTDOWN_MS));
  }

  function snapshotForUndo(message: string): UndoState {
    const store = useExecutionStore.getState();
    return {
      message,
      segmentIndex: store.currentSegmentIndex,
      checkedExerciseIds: store.checkedExerciseIds,
      segmentCycleCounts: store.segmentCycleCounts,
    };
  }

  function handleUndo() {
    if (!undo || undo.segmentIndex !== useExecutionStore.getState().currentSegmentIndex) {
      setUndo(null);
      return;
    }
    const { checkedExerciseIds: checked, segmentCycleCounts: cycles } = undo;
    setUndo(null);
    setSetRest(null);
    commit(() => useExecutionStore.setState({ checkedExerciseIds: checked, segmentCycleCounts: cycles }));
  }

  /** Counts a finished round and clears the round's checklist. */
  function completeRound(message: string) {
    if (!currentSegment) return;
    const key = currentSegment.segment_key;
    const stepIds = buildSegmentStepIds(currentSegment);
    setUndo(snapshotForUndo(message));

    incrementSegmentCycle(key);
    const store = useExecutionStore.getState();
    store.setCheckedExerciseIds(store.checkedExerciseIds.filter((id) => !stepIds.includes(id)));

    const completed = useExecutionStore.getState().segmentCycleCounts[key] ?? 0;
    if (roundTarget !== null && completed >= roundTarget) {
      setUndo(null);
      endCurrentSegment();
    }
    void sync();
  }

  function handleToggleStep(stepId: string) {
    if (!currentSegment) return;
    setFeedback(null);

    const previous = normalizeCheckedExerciseIds(checkedExerciseIds, segmentSteps);
    const wasChecked = previous.includes(stepId);
    const next = wasChecked ? previous.filter((id) => id !== stepId) : [...previous, stepId];
    const finishesSegment =
      !wasChecked && segmentSteps.length > 0 && segmentSteps.every((step) => next.includes(step.stepId));
    const step = segmentSteps.find((candidate) => candidate.stepId === stepId);

    if (!wasChecked) setUndo(snapshotForUndo(i18n("stepDoneToast", { name: step?.exercise.name ?? "" })));
    else setUndo(null);

    setCheckedExerciseIds(next);

    const rest = wasChecked || finishesSegment ? null : setRestSeconds(currentSegment, stepId);
    if (rest !== null) {
      setCountdownNow(Date.now());
      setSetRest({ endsAt: Date.now() + rest * 1000, total: rest, segmentIndex: currentSegmentIndex });
    } else if (wasChecked) {
      setSetRest(null);
    }

    if (finishesSegment && repeatable) {
      completeRound(i18n("roundDoneToast", { round: (roundsCompleted ?? 0) + 1 }));
      return;
    }

    if (finishesSegment && shouldAutoAdvanceOnChecklistComplete(currentSegment)) {
      setUndo(null);
      endCurrentSegment();
    }

    void sync();
  }

  function handleRemoveRound() {
    if (!currentSegment) return;
    setUndo(null);
    commit(() => decrementSegmentCycle(currentSegment.segment_key));
  }

  function handleAddRoundWhilePaused() {
    if (!currentSegment) return;
    setUndo(null);
    commit(() => incrementSegmentCycle(currentSegment.segment_key));
  }

  /** Coach changed the plan: lengthen or shorten the running clock. */
  function handleAdjustTime(deltaSeconds: number) {
    adjustSegmentDuration(currentSegmentIndex, deltaSeconds);
  }

  // ── Lock screen / system media controls ────────────────────────────────────

  const clockSeconds = currentSegment ? displaySeconds(currentSegment, timer.clock) : null;
  const localizedLabel = currentSegment ? segmentLabel(currentSegment, i18n) : "";
  useMediaSession({
    title: clockSeconds ? `${localizedLabel} · ${formatClock(clockSeconds.seconds)}` : localizedLabel,
    subtitle: currentSegment?.section_name ?? "",
    running: isTimerRunning,
    onPlay: () => {
      if (useExecutionStore.getState().status === "paused") handleResume();
    },
    onPause: userPause,
  });

  // ── Render ──────────────────────────────────────────────────────────────────

  const soundControl = (
    <button
      type="button"
      onClick={cycleCueMode}
      aria-label={i18n("timerAlertsLabel", { mode: i18n(CUE_MODE_LABELS[cueMode]) })}
      className="flex min-h-11 items-center gap-2 rounded-xl px-3 text-sm font-semibold"
      style={{
        border: "1px solid var(--border)",
        color: cueMode === "off" ? "var(--dim)" : "var(--text-soft)",
      }}
    >
      <CueModeIcon mode={cueMode} />
      <span>{i18n(CUE_MODE_LABELS[cueMode])}</span>
    </button>
  );

  if (status === "completed") {
    return (
      <div
        className="flex h-dvh flex-col items-center justify-center gap-6 p-8"
        style={{ background: "var(--bg)", color: "var(--text)" }}
      >
        <div className="text-5xl">🏁</div>
        <div className="text-2xl font-bold">{i18n("workoutComplete40f1693")}</div>
        {sectionScores.length > 0 && (
          <div className="w-full max-w-sm space-y-2">
            {sectionScores.map((score, index) => (
              <div
                key={index}
                className="flex justify-between rounded-xl px-4 py-2"
                style={{
                  background: "var(--card, var(--panel-muted))",
                  border: "1px solid var(--border)",
                }}
              >
                <span className="text-sm" style={{ color: "var(--muted)" }}>
                  {score.section_name ??
                    segments.find((segment) => segment.section_id === score.section_id)?.section_name ??
                    score.section_id}
                </span>
                <span className="text-sm font-semibold">
                  <LocalizedScore value={score.value} scoreType={score.score_type} unit={score.unit} />
                </span>
              </div>
            ))}
          </div>
        )}
        <button
          onClick={() => {
            reset();
            router.push("/");
          }}
          className="rounded-2xl px-8 py-3 text-base font-semibold"
          style={{ background: "var(--accent, var(--primary))", color: "var(--primary-contrast)" }}
        >
          {i18n("donee9b450d")}
        </button>
      </div>
    );
  }

  if (!currentSegment) return null;

  if (pendingFinish) {
    return (
      <FinishWizard
        scores={pendingFinish.scores}
        segments={segments}
        initialModifications={inExecutionModifications}
        isSaving={isSaving}
        feedback={feedback}
        onConfirm={(editedScores, modifications) => void confirmPendingFinish(editedScores, modifications)}
        onCancel={() => {
          setFeedback(null);
          setPendingFinish(null);
        }}
      />
    );
  }

  if (awaitingStart) {
    return (
      <div onPointerDownCapture={primeCueAudio}>
        <ReadyScreen
          segments={segments}
          soundControl={soundControl}
          onTestSound={() => {
            primeCueAudio();
            playCue("work", cueMode === "off" ? "sound" : cueMode);
          }}
          onStart={handleStart}
        />
      </div>
    );
  }

  const primaryAction: { label: string; onClick: () => void } = isLastSegment && !repeatable
    ? { label: i18n("finishb74bdee"), onClick: endCurrentSegment }
    : currentSegment.kind === "interval_cycle"
      ? { label: i18n("stopIntervalsLabel"), onClick: endCurrentSegment }
      : repeatable
        ? { label: i18n("addRoundLabel"), onClick: () => completeRound(i18n("roundDoneToast", { round: (roundsCompleted ?? 0) + 1 })) }
        : phase !== "work"
          ? { label: i18n("skipRestLabel"), onClick: skipSegment }
          : { label: i18n("nextbc98198"), onClick: skipSegment };
  const showEndSegmentButton = repeatable && currentSegment.kind !== "interval_cycle";
  const adjustableClock =
    typeof currentSegment.duration_seconds === "number" &&
    (currentSegment.kind === "countdown" || currentSegment.kind === "countup");
  const nextUpText = nextSegment
    ? i18n("nextUpLabel", {
        label:
          nextSegment.section_id !== currentSegment.section_id && !nextSegment.between_sections
            ? `${nextSegment.section_name} · ${segmentLabel(nextSegment, i18n)}`
            : segmentLabel(nextSegment, i18n),
      })
    : null;
  const castRoundText =
    roundsCompleted !== null
      ? roundTarget
        ? i18n("timerRoundLabel", { round: Math.min(roundsCompleted + 1, roundTarget), rounds: roundTarget })
        : i18n("roundNumberLabel", { round: roundsCompleted + 1 })
      : intervalWindow
        ? intervalWindow.count
          ? i18n("timerRoundLabel", { round: intervalWindow.index, rounds: intervalWindow.count })
          : i18n("intervalWindowLabel", { window: intervalWindow.index })
        : currentSegment.round && currentSegment.total_rounds
          ? i18n("timerRoundLabel", { round: currentSegment.round, rounds: currentSegment.total_rounds })
          : null;
  const phaseColor = PHASE_COLORS[phase];
  const nextLimit = nextSegment ? segmentLimitMs(nextSegment) : null;

  return (
    <div
      className="flex h-dvh flex-col overflow-hidden transition-colors"
      style={{
        background: `color-mix(in srgb, ${phaseColor} ${isTimerRunning ? 10 : 4}%, var(--bg))`,
        color: "var(--text)",
      }}
      onPointerDownCapture={primeCueAudio}
    >
      <div className="px-4 pt-3" style={{ borderBottom: "1px solid var(--border)" }}>
        <div className="flex items-center justify-between gap-3 pb-2">
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              {currentSegment.section_name || formatLabels[currentSegment.format as SectionFormat]}
            </div>
            <div className="text-xs" style={{ color: "var(--muted)" }}>
              {i18n("segmentPositionLabel", { current: currentSegmentIndex + 1, total: segments.length })}
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <button
              type="button"
              onClick={() => setCastMode(true)}
              aria-label={i18n("castModeLabel")}
              title={i18n("castModeLabel")}
              className="flex min-h-11 min-w-11 items-center justify-center rounded-xl"
              style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              <CastIcon />
            </button>
            {soundControl}
          </div>
        </div>
        <div
          role="progressbar"
          aria-label={i18n("workoutProgressLabel")}
          aria-valuemin={0}
          aria-valuemax={segments.length}
          aria-valuenow={currentSegmentIndex}
          className="mb-2 h-1.5 overflow-hidden rounded-full"
          style={{ background: "var(--border)" }}
        >
          <div
            className="h-full rounded-full transition-[width]"
            style={{ width: `${(currentSegmentIndex / Math.max(1, segments.length)) * 100}%`, background: phaseColor }}
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-4">
        <TimerDisplay
          segment={currentSegment}
          clock={timer.clock}
          phase={phase}
          running={isTimerRunning}
          roundsCompleted={roundsCompleted}
          roundTarget={roundTarget}
          onRemoveRound={repeatable ? handleRemoveRound : undefined}
          targetReps={targetReps}
          formatLabel={formatLabels[currentSegment.format as SectionFormat] ?? currentSegment.format}
        />

        {nextSegment ? (
          <div
            className="mb-3 flex items-center justify-between gap-3 rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            <span className="min-w-0 truncate">{nextUpText}</span>
            {nextLimit !== null && nextSegment.kind === "countdown" ? (
              <span className="shrink-0 font-mono tabular-nums">{formatClock(Math.round(nextLimit / 1000))}</span>
            ) : null}
          </div>
        ) : null}

        {showSetRest ? (
          <div
            role="timer"
            aria-label={i18n("setRestLabel")}
            className="mb-3 flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
            style={{
              background: `color-mix(in srgb, ${PHASE_COLORS.rest} 16%, var(--bg))`,
              border: `1px solid color-mix(in srgb, ${PHASE_COLORS.rest} 45%, transparent)`,
            }}
          >
            <div className="min-w-0">
              <div className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--text-soft)" }}>
                {i18n("setRestLabel")}
              </div>
              <div
                className={`font-mono text-4xl font-bold tabular-nums ${setRestRemaining <= 3 ? "motion-safe:animate-pulse" : ""}`}
              >
                {formatClock(setRestRemaining)}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <button
                type="button"
                onClick={() => setSetRest((rest) => (rest ? { ...rest, endsAt: rest.endsAt + 15_000, total: rest.total + 15 } : rest))}
                className="min-h-11 rounded-xl px-3 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("addFifteenSecondsLabel")}
              </button>
              <button
                type="button"
                onClick={() => setSetRest(null)}
                className="min-h-11 rounded-xl px-3 text-sm font-bold"
                style={{ background: "var(--accent, var(--primary))", color: "var(--primary-contrast)" }}
              >
                {i18n("skipRestLabel")}
              </button>
            </div>
          </div>
        ) : null}

        {feedback && (
          <div
            role="status"
            className="mb-3 rounded-2xl px-4 py-3 text-sm"
            style={{
              background: "color-mix(in srgb, var(--primary) 12%, transparent)",
              border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
              color: "var(--primary-strong)",
            }}
          >
            {feedback}
          </div>
        )}

        <WorkoutChecklist
          steps={segmentSteps}
          sectionNote={currentSegment.section_note}
          checkedExerciseIds={checkedExerciseIds}
          targetReps={targetReps}
          onToggle={handleToggleStep}
          onModify={(step) => setModifyTarget(step)}
        />
      </div>

      {undo ? (
        <div className="px-4 pb-2" role="status">
          <div
            className="flex items-center justify-between gap-3 rounded-xl px-4 py-2 text-sm"
            style={{ background: "var(--panel-raised, var(--panel))", border: "1px solid var(--border)" }}
          >
            <span className="min-w-0 truncate">{undo.message}</span>
            <button
              type="button"
              onClick={handleUndo}
              className="min-h-11 shrink-0 px-2 font-bold"
              style={{ color: "var(--primary-strong)" }}
            >
              {i18n("editorUndo")}
            </button>
          </div>
        </div>
      ) : null}

      <div
        className="flex items-center gap-3 px-4 pt-3"
        style={{
          borderTop: "1px solid var(--border)",
          paddingBottom: "max(1rem, env(safe-area-inset-bottom))",
        }}
      >
        <button
          type="button"
          onClick={userPause}
          disabled={status !== "active"}
          aria-label={i18n("pausecd21a1b")}
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full disabled:opacity-30"
          style={{ background: "var(--card, var(--panel-muted))", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <PauseIcon />
        </button>
        {currentSegmentIndex > 0 && (
          <button
            type="button"
            onClick={() => goToSegment(currentSegmentIndex - 1)}
            aria-label={i18n("backc32ae9f")}
            className="h-14 w-14 shrink-0 rounded-full text-2xl"
            style={{ background: "var(--card, var(--panel-muted))", border: "1px solid var(--border)", color: "var(--muted)" }}
          >
            <span className="inline-block rtl:rotate-180">‹</span>
          </button>
        )}
        <button
          type="button"
          onClick={primaryAction.onClick}
          disabled={isSaving}
          className="flex h-14 flex-1 items-center justify-center rounded-full text-lg font-bold disabled:opacity-30"
          style={{ background: "var(--accent, var(--primary))", color: "var(--primary-contrast)" }}
        >
          {isSaving ? i18n("saving56a2285") : primaryAction.label}
        </button>
        {showEndSegmentButton ? (
          <button
            type="button"
            onClick={skipSegment}
            aria-label={isLastSegment ? i18n("finishb74bdee") : i18n("nextbc98198")}
            className="h-14 w-14 shrink-0 rounded-full text-2xl"
            style={{ background: "var(--card, var(--panel-muted))", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            <span className="inline-block rtl:rotate-180">{isLastSegment ? "✓" : "›"}</span>
          </button>
        ) : null}
      </div>

      {status === "paused" && !resumeCountdownEndsAt && !showScoreModal && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="execution-paused-title"
          className="fixed inset-0 z-40 flex flex-col items-center justify-center gap-4 px-6"
          style={{ background: "color-mix(in srgb, var(--bg) 92%, transparent)" }}
        >
          <div id="execution-paused-title" className="mb-2 text-4xl font-bold" style={{ color: "var(--text)" }}>
            {i18n("pausedc7dfb6f")}
          </div>
          {feedback ? (
            <p className="max-w-xs text-center text-sm" style={{ color: "var(--primary-strong)" }}>
              {feedback}
            </p>
          ) : null}
          <button
            type="button"
            onClick={handleResume}
            autoFocus
            className="w-full max-w-xs rounded-2xl py-4 text-xl font-bold"
            style={{ background: "var(--accent, var(--primary))", color: "var(--primary-contrast)" }}
          >
            {i18n("resumeb3bd0b5")}
          </button>
          {adjustableClock ? (
            <div className="flex w-full max-w-xs items-center justify-between gap-2" role="group" aria-label={i18n("adjustTimeLabel")}>
              <button
                type="button"
                onClick={() => handleAdjustTime(-30)}
                className="min-h-12 flex-1 rounded-2xl text-base font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("minusThirtySecondsLabel")}
              </button>
              <span className="min-w-16 text-center font-mono text-lg font-bold tabular-nums">
                {formatClock(currentSegment.duration_seconds ?? 0)}
              </span>
              <button
                type="button"
                onClick={() => handleAdjustTime(30)}
                className="min-h-12 flex-1 rounded-2xl text-base font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("plusThirtySecondsLabel")}
              </button>
            </div>
          ) : null}
          {repeatable ? (
            <div className="flex w-full max-w-xs items-center justify-between gap-2" role="group" aria-label={i18n("adjustRoundsLabel")}>
              <button
                type="button"
                onClick={handleRemoveRound}
                disabled={(roundsCompleted ?? 0) === 0}
                aria-label={i18n("removeRoundLabel")}
                className="min-h-12 flex-1 rounded-2xl text-xl font-semibold disabled:opacity-30"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                −
              </button>
              <span className="min-w-16 text-center text-sm font-semibold">
                {i18n("roundsDoneLabel", { count: roundsCompleted ?? 0 })}
              </span>
              <button
                type="button"
                onClick={handleAddRoundWhilePaused}
                aria-label={i18n("addRoundLabel")}
                className="min-h-12 flex-1 rounded-2xl text-xl font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                +
              </button>
            </div>
          ) : null}
          <button
            type="button"
            onClick={() => handleFinish()}
            disabled={isSaving}
            className="w-full max-w-xs rounded-2xl py-3 text-base font-semibold disabled:opacity-30"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("endWorkoutLabel")}
          </button>
        </div>
      )}

      {resumeCountdown !== null && (
        <div
          role="timer"
          className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-4 px-6"
          style={{ background: `color-mix(in srgb, ${PHASE_COLORS.transition} 12%, var(--bg))` }}
        >
          <div className="text-lg font-bold uppercase tracking-widest" style={{ color: "var(--text-soft)" }}>
            {isGetReadyCountdown ? i18n("getReadyLabel") : i18n("resumeb3bd0b5")}
          </div>
          <div
            className="font-mono font-bold tabular-nums leading-none"
            style={{ color: "var(--text)", fontSize: "clamp(6rem, 40vw, 14rem)" }}
          >
            {resumeCountdown}
          </div>
          <div className="text-center text-base" style={{ color: "var(--text-soft)" }}>
            {currentSegment.section_name ? `${currentSegment.section_name} · ` : ""}
            {segmentLabel(currentSegment, i18n)}
          </div>
        </div>
      )}

      {castMode && clockSeconds ? (
        <CastView
          seconds={clockSeconds.seconds}
          phase={phase}
          label={localizedLabel}
          sectionName={currentSegment.section_name}
          roundText={castRoundText}
          nextText={nextUpText}
          finalSeconds={isTimerRunning && clockSeconds.countsDown && clockSeconds.seconds > 0 && clockSeconds.seconds <= 3}
          paused={status === "paused"}
          onExit={exitCastMode}
        />
      ) : null}

      {modifyTarget && (
        <ModificationModal
          segment={currentSegment}
          step={modifyTarget}
          onSave={(mod) => {
            setInExecutionModifications((prev) => {
              const without = prev.filter((m) => (m.patch_id ?? "") !== (mod.patch_id ?? ""));
              return [...without, mod];
            });
            setModifyTarget(null);
          }}
          onClose={() => setModifyTarget(null)}
        />
      )}

      {showScoreModal && currentSegment.scoreable && (
        <ScoreModal
          segment={currentSegment}
          existingScore={(() => {
            const existing = sectionScores.find((score) => score.section_id === currentSegment.section_id);

            if (existing?.kind === "final") {
              return existing;
            }

            return (
              computeMeasuredScore(currentSegment, {
                checkedExerciseIds,
                sectionElapsedMs,
                segmentCycleCounts,
                currentSegment,
                currentElapsedMs: pausedElapsed,
              }) ?? existing ?? undefined
            );
          })()}
          isSaving={isSaving}
          onSave={async (score) => {
            const finalScore = { ...score, source: "manual", kind: "final" };
            const nextScores = mergeSectionScore(sectionScores, finalScore);

            if (isLastSegment) {
              upsertScore(finalScore);
              handleFinish(nextScores);
              return;
            }

            const now = Date.now();
            commit(() => {
              upsertScore(finalScore);
              moveToSegment(currentSegmentIndex + 1, {
                elapsedMs: useExecutionStore.getState().currentElapsedMs(now),
                startedAt: now,
              });
              resumeTimer(now);
            });
            setShowScoreModal(false);
          }}
          onClose={() => setShowScoreModal(false)}
        />
      )}
    </div>
  );
}
