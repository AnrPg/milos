"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import {
  addExecutionModifications,
  completeExecution as completeExecutionRequest,
  type ExerciseModification,
  type ExerciseNote,
  type ExecutionProgressPayload,
  type TimerSegment,
  updateExecutionProgress,
  type WorkoutExecution,
} from "@/api/executions";
import { useSession } from "@/components/session-provider";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useWorkoutTimer } from "@/hooks/useWorkoutTimer";
import { subscribeToTopic } from "@/lib/realtime";
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
import {
  isOfflineFailure,
  queueOfflineCheckoff,
  reconcileOfflineCheckoffs,
} from "@/lib/offline-execution-queue";
import { useExecutionStore } from "@/stores/execution";

import { FinishWizard } from "./FinishWizard";
import { ModificationModal } from "./ModificationModal";
import { ScoreModal } from "./ScoreModal";
import {
  buildSegmentStepIds,
  computeMeasuredScore,
  isLastSegmentOfSection,
  isRepeatableSegment,
  shouldAutoAdvanceOnChecklistComplete,
} from "./progress";
import { TimerDisplay } from "./TimerDisplay";
import { type ChecklistStep, WorkoutChecklist } from "./WorkoutChecklist";
import { LocalizedScore } from "@/components/localized-score";

function mergeSectionScore(
  scores: {
    section_id: string;
    value: number | string;
    unit?: string;
    score_type?: string;
    source?: string;
    kind?: string;
  }[],
  nextScore: {
    section_id: string;
    value: number | string;
    unit?: string;
    score_type?: string;
    source?: string;
    kind?: string;
  },
) {
  const existing = scores.findIndex((score) => score.section_id === nextScore.section_id);

  if (existing >= 0) {
    return scores.map((score, index) => (index === existing ? nextScore : score));
  }

  return [...scores, nextScore];
}

function normalizeCheckedExerciseIds(
  checkedExerciseIds: string[],
  segmentSteps: ChecklistStep[],
) {
  const next = checkedExerciseIds.filter((id) => {
    if (!segmentSteps.some((step) => step.exerciseId === id)) {
      return true;
    }

    return segmentSteps.some((step) => step.stepId === id);
  });

  for (const exerciseId of new Set(segmentSteps.map((step) => step.exerciseId))) {
    if (checkedExerciseIds.includes(exerciseId)) {
      next.push(
        ...segmentSteps
          .filter((step) => step.exerciseId === exerciseId)
          .map((step) => step.stepId),
      );
    }
  }

  return Array.from(new Set(next));
}

function isRestSegment(segment: TimerSegment) {
  return segment.format === "rest" || (segment.kind === "countdown" && segment.exercises.length === 0);
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

export function ExecutionMode() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { tokens } = useSession();

  const {
    executionId,
    segments,
    currentSegmentIndex,
    status,
    segmentStartedAt,
    pausedElapsed,
    resumeCountdownEndsAt,
    sectionElapsedMs,
    segmentCycleCounts,
    checkedExerciseIds,
    sectionScores,
    pauseTimer,
    startResumeCountdown,
    resumeTimer,
    advanceSegment,
    jumpToSegment,
    commitSegmentElapsed,
    incrementSegmentCycle,
    setCheckedExerciseIds,
    upsertScore,
    upsertNote,
    hydrateFromExecution,
    completeExecution,
    reset,
  } = useExecutionStore();

  const [showScoreModal, setShowScoreModal] = useState(false);
  const [scoreTransitionLocked, setScoreTransitionLocked] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [countdownNow, setCountdownNow] = useState(() => Date.now());
  const [inExecutionModifications, setInExecutionModifications] = useState<ExerciseModification[]>([]);
  const [modifyTarget, setModifyTarget] = useState<ChecklistStep | null>(null);
  const [pendingFinish, setPendingFinish] = useState<{
    scores: typeof sectionScores;
    checkedExerciseIds: string[];
    includeCurrentElapsed: boolean;
    elapsedSnapshot: number;
  } | null>(null);

  const [cueMode, setCueMode] = useState<CueMode>(() => readCueMode());

  const currentSegment = segments[currentSegmentIndex] ?? null;
  const isActive = status === "active";
  const isLastSegment = currentSegmentIndex === segments.length - 1;
  const isTimerRunning = isActive && !showScoreModal && !scoreTransitionLocked;
  // Interval formats split one section into many segments; only the section's
  // final segment asks for a score so Tabata/EMOM never interrupt every interval.
  const promptsForScore =
    Boolean(currentSegment?.scoreable) && isLastSegmentOfSection(segments, currentSegmentIndex);

  const { elapsed, remaining, isExpired } = useWorkoutTimer(
    currentSegment,
    isTimerRunning,
    pausedElapsed,
    segmentStartedAt,
  );

  const resumeCountdown = useMemo(() => {
    if (!resumeCountdownEndsAt) {
      return null;
    }

    return Math.max(0, Math.ceil((resumeCountdownEndsAt - countdownNow) / 1000));
  }, [countdownNow, resumeCountdownEndsAt]);

  async function persistProposedMutation(
    mutate: () => void,
    snapshot: { currentSegment: TimerSegment | null; currentElapsedMs: number },
  ) {
    if (!tokens?.access_token || !executionId) return null;

    const before = useExecutionStore.getState();
    mutate();
    const payload = useExecutionStore.getState().buildProgressPayload(snapshot);
    useExecutionStore.setState(before, true);

    if (!payload) return null;

    const execution = await updateExecutionProgress(tokens.access_token, executionId, payload);
    hydrateFromExecution(execution);
    return execution;
  }

  async function doFinish(
    finalSectionScores: typeof sectionScores,
    finalCheckedExerciseIds: string[],
    includeCurrentElapsed: boolean,
    elapsedSnapshot: number,
  ) {
    if (!tokens?.access_token || !executionId) return false;
    setIsSaving(true);
    setFeedback(null);

    try {
      const freshStore = useExecutionStore.getState();
      const freshSectionElapsedMs = freshStore.sectionElapsedMs;

      const completionSectionElapsedMs =
        includeCurrentElapsed && currentSegment
          ? {
              ...freshSectionElapsedMs,
              [currentSegment.section_id]:
                (freshSectionElapsedMs[currentSegment.section_id] ?? 0) + elapsedSnapshot * 1000,
            }
          : freshSectionElapsedMs;

      const execution = await completeExecutionRequest(tokens.access_token, executionId, {
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        checked_exercise_ids: finalCheckedExerciseIds,
        section_scores: finalSectionScores,
        exercise_notes: freshStore.exerciseNotes,
        total_elapsed_ms: freshStore.totalElapsedMs + (includeCurrentElapsed ? elapsedSnapshot * 1000 : 0),
        section_elapsed_ms: completionSectionElapsedMs,
        segment_cycle_counts: freshStore.segmentCycleCounts,
      });
      hydrateFromExecution(execution);
      completeExecution();
      return true;
    } catch {
      setFeedback(i18n("workoutCompletionCouldNotBeSavedTryAgaindce610c"));
      return false;
    } finally {
      setIsSaving(false);
    }
  }

  async function handleFinish(
    finalSectionScores = sectionScores,
    finalCheckedExerciseIds = checkedExerciseIds,
    includeCurrentElapsed = true,
  ) {
    if (!tokens?.access_token || !executionId) return false;

    // Freeze the clock while the athlete reviews, so backing out of the review
    // returns to a paused workout instead of one that kept running underneath.
    // A persisted pause folds the current segment's elapsed time into the
    // stored totals, so completion must not add it a second time.
    let elapsedAlreadyCounted = useExecutionStore.getState().status === "paused";

    if (useExecutionStore.getState().status === "active") {
      try {
        await persistProposedMutation(
          () => pauseTimer(Date.now()),
          { currentSegment, currentElapsedMs: elapsed * 1000 },
        );
        elapsedAlreadyCounted = true;
      } catch {
        setFeedback(i18n("pauseCouldNotBeSyncedTryAgain5a0fece"));
      }
    }

    // Always show the review screen before submitting so the user can confirm.
    setShowScoreModal(false);
    setPendingFinish({
      scores: finalSectionScores,
      checkedExerciseIds: finalCheckedExerciseIds,
      includeCurrentElapsed: elapsedAlreadyCounted ? false : includeCurrentElapsed,
      elapsedSnapshot: elapsed,
    });
    return true;
  }

  async function confirmPendingFinish(editedScores: typeof sectionScores, modifications: ExerciseModification[]) {
    if (!pendingFinish) return;
    const { checkedExerciseIds: ids, includeCurrentElapsed, elapsedSnapshot } = pendingFinish;

    try {
      if (modifications.length > 0 && tokens?.access_token && executionId) {
        const execution =
          await addExecutionModifications(tokens.access_token, executionId, modifications);
        hydrateFromExecution(execution);
      }

      const completed = await doFinish(editedScores, ids, includeCurrentElapsed, elapsedSnapshot);
      if (completed) setPendingFinish(null);
    } catch {
      setFeedback(i18n("workoutChangesCouldNotBeSavedReviewThemaa17dac"));
    }
  }

  async function movePastCurrentSegment(
    finalSectionScores = sectionScores,
    finalCheckedExerciseIds = checkedExerciseIds,
  ) {
    if (isLastSegment) {
      return handleFinish(finalSectionScores, finalCheckedExerciseIds, false);
    }

    try {
      await persistProposedMutation(
        () => {
          if (currentSegment) commitSegmentElapsed(currentSegment.section_id, elapsed * 1000);
          advanceSegment(Date.now());
        },
        { currentSegment: null, currentElapsedMs: 0 },
      );
      return true;
    } catch {
      setFeedback(i18n("workoutProgressCouldNotBeSavedTryAgain654eacf"));
      return false;
    }
  }

  async function openScoreModal() {
    setScoreTransitionLocked(true);

    if (status === "active") {
      try {
        await persistProposedMutation(
          () => pauseTimer(Date.now()),
          { currentSegment, currentElapsedMs: elapsed * 1000 },
        );
      } catch {
        setFeedback(i18n("timerStateCouldNotBeSyncedTryAgainef30d57"));
        setScoreTransitionLocked(false);
        return;
      }
    }

    setShowScoreModal(true);
  }

  const handleExpiredSegment = useEffectEvent(() => {
    if (promptsForScore) {
      void openScoreModal();
    } else if (isLastSegment) {
      void handleFinish();
    } else {
      void movePastCurrentSegment();
    }
  });

  useEffect(() => {
    if (!isExpired || status !== "active" || showScoreModal || scoreTransitionLocked) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      handleExpiredSegment();
    }, 0);

    return () => window.clearTimeout(timeoutId);
  }, [isExpired, scoreTransitionLocked, showScoreModal, status]);

  useEffect(() => {
    if (resumeCountdownEndsAt === null) {
      return;
    }

    const intervalId = window.setInterval(() => {
      setCountdownNow(Date.now());
    }, 250);

    return () => window.clearInterval(intervalId);
  }, [resumeCountdownEndsAt]);

  const resumeAfterCountdown = useEffectEvent(() => {
    void persistProposedMutation(
      () => resumeTimer(Date.now()),
      { currentSegment, currentElapsedMs: 0 },
    ).catch(() => {
      setFeedback(i18n("resumeCouldNotBeSyncedTryAgaindef7342"));
    });
  });

  useEffect(() => {
    if (!resumeCountdownEndsAt || countdownNow < resumeCountdownEndsAt) {
      return;
    }

    resumeAfterCountdown();
  }, [countdownNow, resumeCountdownEndsAt]);

  useScreenWakeLock(status !== "completed");

  // Audio/haptic cues: phase start (work vs rest) and the last 3 seconds.
  const previousCueRef = useRef<CueSnapshot | null>(null);
  const cueSegmentKey = currentSegment?.segment_key ?? null;
  const cuePhase = currentSegment && isRestSegment(currentSegment) ? "rest" : "work";

  useEffect(() => {
    const snapshot: CueSnapshot = {
      segmentKey: cueSegmentKey,
      running: isTimerRunning,
      remaining,
      phase: cuePhase,
    };
    const cue = nextCue(previousCueRef.current, snapshot);
    previousCueRef.current = snapshot;
    if (cue) playCue(cue, cueMode);
  }, [cueMode, cuePhase, cueSegmentKey, isTimerRunning, remaining]);

  useEffect(() => {
    if (resumeCountdown !== null && resumeCountdown > 0) playCue("tick", cueMode);
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

    return subscribeToTopic(tokens.access_token, "execution:" + (executionId), {
      "execution:progress_updated": (payload) => {
        if (isExecutionPayload(payload)) {
          hydrateFromExecution(payload.execution);
        }
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
  }, [completeExecution, executionId, hydrateFromExecution, tokens?.access_token, upsertNote]);

  useEffect(() => {
    if (!tokens?.access_token || !executionId) return;

    const reconcile = () => {
      void reconcileOfflineCheckoffs(
        tokens.access_token,
        executionId,
        hydrateFromExecution,
      ).catch(() => undefined);
    };

    reconcile();
    window.addEventListener("online", reconcile);
    return () => window.removeEventListener("online", reconcile);
  }, [executionId, hydrateFromExecution, tokens?.access_token]);

  function handlePause() {
    void persistProposedMutation(
      () => pauseTimer(Date.now()),
      { currentSegment, currentElapsedMs: elapsed * 1000 },
    ).catch(() => {
      setFeedback(i18n("pauseCouldNotBeSyncedTryAgain5a0fece"));
    });
  }

  function handleResume() {
    const endsAt = Date.now() + 3_000;

    void persistProposedMutation(
      () => startResumeCountdown(endsAt),
      { currentSegment, currentElapsedMs: 0 },
    ).catch(() => {
      setFeedback(i18n("resumeCountdownCouldNotBeSyncedTryAgainf2572b6"));
    });
  }

  function handleNext() {
    if (promptsForScore) {
      void openScoreModal();
    } else {
      void movePastCurrentSegment();
    }
  }

  async function handleToggleCheckoff(stepId: string, segmentSteps: ChecklistStep[]) {
    if (!tokens?.access_token || !executionId) return;

    setFeedback(null);

    const previous = normalizeCheckedExerciseIds(checkedExerciseIds, segmentSteps);
    const next = previous.includes(stepId)
      ? previous.filter((id) => id !== stepId)
      : [...previous, stepId];
    const segmentStepIds = segmentSteps.map((step) => step.stepId);
    const isSegmentComplete =
      segmentStepIds.length > 0 &&
      segmentStepIds.every((id) => (id === stepId ? next.includes(id) : next.includes(id)));

    setCheckedExerciseIds(next);

    let lastConfirmedExecution: WorkoutExecution | null = null;
    let attemptedPayload: ExecutionProgressPayload | null = null;

    try {
      const payload = useExecutionStore.getState().buildProgressPayload({
        currentSegment,
        currentElapsedMs: elapsed * 1000,
      });

      if (!payload) {
        throw new Error(i18n("missingExecutionPayload5f49431"));
      }

      attemptedPayload = payload;

      const execution = await updateExecutionProgress(tokens.access_token, executionId, {
        ...payload,
        checked_exercise_ids: next,
      });

      lastConfirmedExecution = execution;
      hydrateFromExecution(execution);

      if (!previous.includes(stepId) && isSegmentComplete) {
        if (currentSegment && isRepeatableSegment(currentSegment)) {
          incrementSegmentCycle(currentSegment.segment_key);
          const segmentStepIds = buildSegmentStepIds(currentSegment);
          const rolledForward = next.filter((id) => !segmentStepIds.includes(id));
          setCheckedExerciseIds(rolledForward);

          const rolledPayload = useExecutionStore.getState().buildProgressPayload({
            currentSegment,
            currentElapsedMs: elapsed * 1000,
          });

          if (!rolledPayload) {
            throw new Error(i18n("missingRolledForwardExecutionPayload9410f3a"));
          }

          const rolledExecution = await updateExecutionProgress(tokens.access_token, executionId, {
            ...rolledPayload,
            checked_exercise_ids: rolledForward,
          });

          lastConfirmedExecution = rolledExecution;
          hydrateFromExecution(rolledExecution);
          return;
        }

        if (promptsForScore && currentSegment && shouldAutoAdvanceOnChecklistComplete(currentSegment)) {
          await openScoreModal();
        } else if (currentSegment && shouldAutoAdvanceOnChecklistComplete(currentSegment)) {
          await movePastCurrentSegment(sectionScores, execution.checked_exercise_ids);
        }
      }
    } catch (error) {
      if (!lastConfirmedExecution && attemptedPayload && isOfflineFailure(error)) {
        await queueOfflineCheckoff(executionId, attemptedPayload, previous, next);
        setFeedback(i18n("savedOfflineThisCheckOffWillSyncAutomatically2fcff20"));
        return;
      }

      if (lastConfirmedExecution) {
        hydrateFromExecution(lastConfirmedExecution);
        setFeedback(i18n("theRepeatCycleWasNotSavedRestoredThef0c5693"));
      } else {
        setCheckedExerciseIds(previous);
        setFeedback(i18n("checkOffCouldNotBeSavedYourLast2441073"));
      }
    }
  }

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

  return (
    <div
      className="flex h-dvh flex-col overflow-hidden"
      style={{ background: "var(--bg)", color: "var(--text)" }}
      onPointerDownCapture={primeCueAudio}
    >
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <div className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {currentSegmentIndex + 1} / {segments.length}
        </div>
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
      </div>

      <div className="flex-shrink-0 px-4">
        <TimerDisplay
          segment={currentSegment}
          elapsed={elapsed}
          remaining={remaining}
          isExpired={isExpired}
        />
      </div>

      {feedback && (
        <div className="px-4 pb-2">
          <div
            className="rounded-2xl px-4 py-3 text-sm"
            style={{
              background: "color-mix(in srgb, var(--primary) 12%, transparent)",
              border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
              color: "var(--primary-strong)",
            }}
          >
            {feedback}
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto px-4 pb-4">
        <WorkoutChecklist
          segment={currentSegment}
          checkedExerciseIds={checkedExerciseIds}
          onToggle={(stepId, segmentSteps) => {
            void handleToggleCheckoff(stepId, segmentSteps);
          }}
          onModify={(step) => setModifyTarget(step)}
        />
      </div>

      <div
        className="flex gap-3 px-4 pt-4"
        style={{
          borderTop: "1px solid var(--border)",
          paddingBottom: "max(1rem, env(safe-area-inset-bottom))",
        }}
      >
        <button
          type="button"
          onClick={handlePause}
          disabled={status !== "active"}
          aria-label={i18n("pausecd21a1b")}
          className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full disabled:opacity-30"
          style={{
            background: "var(--card, var(--panel-muted))",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        >
          <PauseIcon />
        </button>
        {currentSegmentIndex > 0 && (
          <button
            onClick={() => {
              void persistProposedMutation(
                () => jumpToSegment(currentSegmentIndex - 1, Date.now()),
                { currentSegment, currentElapsedMs: elapsed * 1000 },
              ).catch(() => {
                setFeedback(i18n("navigationCouldNotBeSyncedTryAgaina8045ae"));
              });
            }}
            className="h-12 w-12 rounded-full text-xl"
            style={{
              background: "var(--card, var(--panel-muted))",
              border: "1px solid var(--border)",
              color: "var(--muted)",
            }}
          >
            <span className="inline-block rtl:rotate-180">‹</span>
          </button>
        )}
        <button
          onClick={() => {
            if (isLastSegment) {
              void handleFinish();
            } else {
              handleNext();
            }
          }}
          disabled={isSaving}
          className="flex h-12 flex-1 items-center justify-center rounded-full text-base font-bold disabled:opacity-30"
          style={{ background: "var(--accent, var(--primary))", color: "var(--primary-contrast)" }}
        >
          {isSaving ? i18n("saving56a2285") : isLastSegment ? i18n("finishb74bdee") : i18n("next2f04eb1")}
        </button>
      </div>

      {status === "paused" && !resumeCountdownEndsAt && !showScoreModal && !scoreTransitionLocked && (
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
          <button
            type="button"
            onClick={() => void handleFinish()}
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
          className="fixed inset-0 z-50 flex items-center justify-center"
          style={{ background: "color-mix(in srgb, var(--bg) 92%, transparent)" }}
        >
          <div
            className="font-mono text-9xl font-bold tabular-nums"
            style={{ color: "var(--accent, var(--primary))" }}
          >
            {resumeCountdown}
          </div>
        </div>
      )}

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
            const existing = sectionScores.find(
              (score) => score.section_id === currentSegment.section_id,
            );

            if (existing?.kind === "final") {
              return existing;
            }

            return (
              computeMeasuredScore(currentSegment, {
                checkedExerciseIds,
                sectionElapsedMs,
                segmentCycleCounts,
                currentSegment,
                currentElapsedMs: elapsed * 1000,
              }) ?? existing ?? undefined
            );
          })()}
          isSaving={isSaving}
          onSave={async (score) => {
            const finalScore = { ...score, source: "manual", kind: "final" };
            const nextScores = mergeSectionScore(sectionScores, finalScore);

            if (isLastSegment) {
              const completed = await handleFinish(nextScores);

              if (completed) {
                setScoreTransitionLocked(false);
                setShowScoreModal(false);
              }

              return;
            }

            try {
              await persistProposedMutation(
                () => {
                  upsertScore(finalScore);
                  advanceSegment(Date.now());
                },
                { currentSegment: null, currentElapsedMs: 0 },
              );
              setScoreTransitionLocked(false);
              setShowScoreModal(false);
            } catch {
              setFeedback(i18n("scoreAndNavigationCouldNotBeSavedYourfab62fd"));
            }
          }}
          onClose={() => {
            setScoreTransitionLocked(false);
            setShowScoreModal(false);
          }}
        />
      )}
    </div>
  );
}
