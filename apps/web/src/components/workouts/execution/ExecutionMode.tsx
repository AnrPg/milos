"use client";

import React, { useEffect, useEffectEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import {
  addExecutionModifications,
  completeExecution as completeExecutionRequest,
  type ExerciseModification,
  type ExerciseNote,
  type TimerSegment,
  updateExecutionProgress,
  type WorkoutExecution,
} from "@/api/executions";
import { useSession } from "@/components/session-provider";
import { useWorkoutTimer } from "@/hooks/useWorkoutTimer";
import { subscribeToTopic } from "@/lib/realtime";
import { useExecutionStore } from "@/stores/execution";

import { FinishWizard } from "./FinishWizard";
import { ModificationModal } from "./ModificationModal";
import { ScoreModal } from "./ScoreModal";
import {
  buildSegmentStepIds,
  computeMeasuredScore,
  isRepeatableSegment,
  shouldAutoAdvanceOnChecklistComplete,
} from "./progress";
import { TimerDisplay } from "./TimerDisplay";
import { type ChecklistStep, WorkoutChecklist } from "./WorkoutChecklist";

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

function isExecutionPayload(value: unknown): value is { execution: WorkoutExecution } {
  return (
    typeof value === "object" &&
    value !== null &&
    "execution" in value &&
    typeof value.execution === "object" &&
    value.execution !== null
  );
}

export function ExecutionMode() {
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
    buildProgressPayload,
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

  const currentSegment = segments[currentSegmentIndex] ?? null;
  const isActive = status === "active";
  const isLastSegment = currentSegmentIndex === segments.length - 1;
  const isTimerRunning = isActive && !showScoreModal && !scoreTransitionLocked;

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

  async function persistProgressFromStore() {
    return persistProgressSnapshot({
      currentSegment,
      currentElapsedMs: elapsed * 1000,
    });
  }

  async function persistProgressSnapshot(snapshot: {
    currentSegment: TimerSegment | null;
    currentElapsedMs: number;
  }) {
    if (!tokens?.access_token || !executionId) {
      return null;
    }

    const payload = buildProgressPayload(snapshot);
    if (!payload) {
      return null;
    }

    const execution = await updateExecutionProgress(tokens.access_token, executionId, payload);
    hydrateFromExecution(execution);
    return execution;
  }

  const persistProgressFromStoreEvent = useEffectEvent(() => {
    void persistProgressFromStore().catch(() => {
      setFeedback("Workout progress could not be synced. Try again.");
    });
  });

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
      setFeedback("Workout completion could not be saved. Try again.");
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

    // Always show the review screen before submitting so the user can confirm.
    setShowScoreModal(false);
    setPendingFinish({
      scores: finalSectionScores,
      checkedExerciseIds: finalCheckedExerciseIds,
      includeCurrentElapsed,
      elapsedSnapshot: elapsed,
    });
    return true;
  }

  async function confirmPendingFinish(editedScores: typeof sectionScores, modifications: ExerciseModification[]) {
    if (!pendingFinish) return;
    const { checkedExerciseIds: ids, includeCurrentElapsed, elapsedSnapshot } = pendingFinish;
    setPendingFinish(null);
    if (modifications.length > 0 && tokens?.access_token && executionId) {
      await addExecutionModifications(tokens.access_token, executionId, modifications);
    }
    await doFinish(editedScores, ids, includeCurrentElapsed, elapsedSnapshot);
  }

  async function movePastCurrentSegment(
    finalSectionScores = sectionScores,
    finalCheckedExerciseIds = checkedExerciseIds,
  ) {
    if (currentSegment) {
      commitSegmentElapsed(currentSegment.section_id, elapsed * 1000);
    }

    if (isLastSegment) {
      return handleFinish(finalSectionScores, finalCheckedExerciseIds, false);
    }

    advanceSegment(Date.now());

    try {
      await persistProgressSnapshot({
        currentSegment: null,
        currentElapsedMs: 0,
      });
      return true;
    } catch {
      setFeedback("Workout progress could not be saved. Try again.");
      return false;
    }
  }

  async function openScoreModal() {
    setScoreTransitionLocked(true);

    if (status === "active") {
      pauseTimer(Date.now());

      try {
        await persistProgressFromStore();
      } catch {
        setFeedback("Timer state could not be synced. Your score can still be entered.");
      }
    }

    setShowScoreModal(true);
  }

  const handleExpiredSegment = useEffectEvent(() => {
    if (currentSegment?.scoreable) {
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

  useEffect(() => {
    if (!resumeCountdownEndsAt || countdownNow < resumeCountdownEndsAt) {
      return;
    }

    resumeTimer(Date.now());
    persistProgressFromStoreEvent();
  }, [countdownNow, resumeCountdownEndsAt, resumeTimer]);

  useEffect(() => {
    if (!tokens?.access_token || !executionId) return;

    return subscribeToTopic(tokens.access_token, `execution:${executionId}`, {
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

  function handlePause() {
    pauseTimer(Date.now());

    void persistProgressFromStore().catch(() => {
      setFeedback("Pause could not be synced. Try again.");
    });
  }

  function handleResume() {
    const endsAt = Date.now() + 3_000;
    startResumeCountdown(endsAt);

    void persistProgressFromStore().catch(() => {
      setFeedback("Resume countdown could not be synced. Try again.");
    });
  }

  function handleNext() {
    if (currentSegment?.scoreable) {
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

    try {
      const payload = useExecutionStore.getState().buildProgressPayload({
        currentSegment,
        currentElapsedMs: elapsed * 1000,
      });

      if (!payload) {
        throw new Error("Missing execution payload");
      }

      const execution = await updateExecutionProgress(tokens.access_token, executionId, {
        ...payload,
        checked_exercise_ids: next,
      });

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
            throw new Error("Missing rolled-forward execution payload");
          }

          const rolledExecution = await updateExecutionProgress(tokens.access_token, executionId, {
            ...rolledPayload,
            checked_exercise_ids: rolledForward,
          });

          hydrateFromExecution(rolledExecution);
          return;
        }

        if (currentSegment?.scoreable && shouldAutoAdvanceOnChecklistComplete(currentSegment)) {
          await openScoreModal();
        } else if (currentSegment && shouldAutoAdvanceOnChecklistComplete(currentSegment)) {
          await movePastCurrentSegment(sectionScores, execution.checked_exercise_ids);
        }
      }
    } catch {
    setCheckedExerciseIds(previous);
      setFeedback("Check-off could not be saved. Your last change was rolled back.");
    }
  }

  if (status === "completed") {
    return (
      <div
        className="flex h-screen flex-col items-center justify-center gap-6 p-8"
        style={{ background: "var(--bg)", color: "var(--text)" }}
      >
        <div className="text-5xl">🏁</div>
        <div className="text-2xl font-bold">Workout Complete</div>
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
                  {score.value} {score.unit ?? ""}
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
          style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
        >
          Done
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
      />
    );
  }

  return (
    <div
      className="flex h-screen flex-col overflow-hidden"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <button
          onClick={handlePause}
          className="rounded-xl p-2 text-sm"
          style={{ color: "var(--muted)" }}
        >
          ‹ Pause
        </button>
        <div className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {currentSegmentIndex + 1} / {segments.length}
        </div>
        <button
          onClick={() => {
            if (currentSegment?.scoreable) {
              void openScoreModal();
            } else {
              void handleFinish();
            }
          }}
          disabled={isSaving}
          className="rounded-xl px-3 py-1.5 text-sm font-semibold disabled:opacity-30"
          style={{ color: "var(--accent, var(--primary))" }}
        >
          Finish
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
        className="flex gap-3 px-4 py-4"
        style={{ borderTop: "1px solid var(--border)" }}
      >
        {currentSegmentIndex > 0 && (
          <button
            onClick={() => {
              jumpToSegment(currentSegmentIndex - 1, Date.now());
              void persistProgressFromStore().catch(() => {
                setFeedback("Navigation could not be synced. Try again.");
              });
            }}
            className="h-12 w-12 rounded-full text-xl"
            style={{
              background: "var(--card, var(--panel-muted))",
              border: "1px solid var(--border)",
              color: "var(--muted)",
            }}
          >
            ‹
          </button>
        )}
        <button
          onClick={() => {
            if (isLastSegment) {
              if (currentSegment?.scoreable) {
                void openScoreModal();
              } else {
                void handleFinish();
              }
            } else {
              handleNext();
            }
          }}
          disabled={isSaving}
          className="flex h-12 flex-1 items-center justify-center rounded-full text-base font-bold disabled:opacity-30"
          style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
        >
          {isSaving ? "Saving…" : isLastSegment ? "Finish" : "Next →"}
        </button>
      </div>

      {status === "paused" && !resumeCountdownEndsAt && (
        <div
          className="absolute inset-0 z-40 flex flex-col items-center justify-center gap-6"
          style={{ background: "color-mix(in srgb, var(--bg) 92%, transparent)" }}
        >
          <div className="text-4xl font-bold" style={{ color: "var(--text)" }}>
            Paused
          </div>
          <button
            onClick={handleResume}
            className="rounded-2xl px-10 py-4 text-xl font-bold"
            style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
          >
            Resume
          </button>
        </div>
      )}

      {resumeCountdown !== null && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center"
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
          step={modifyTarget}
          onSave={(mod) => {
            setInExecutionModifications((prev) => {
              const without = prev.filter((m) => m.exercise_id !== mod.exercise_id);
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
            const nextScores = mergeSectionScore(sectionScores, score);
            upsertScore(score);

            if (isLastSegment) {
              const completed = await handleFinish(nextScores);

              if (completed) {
                setScoreTransitionLocked(false);
                setShowScoreModal(false);
              }

              return;
            }

            setScoreTransitionLocked(false);
            setShowScoreModal(false);
            advanceSegment(Date.now());

            try {
              await persistProgressFromStore();
            } catch {
              setFeedback("Workout progress could not be saved. Try again.");
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
