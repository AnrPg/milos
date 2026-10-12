"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import {
  addExecutionModifications,
  completeExecution as completeExecutionRequest,
  fetchExecution,
  startExecution,
  type ExerciseModification,
  type SectionScore,
} from "@/api/executions";
import { fetchWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import {
  clearFreeTextExecutionWorkout,
  readFreeTextExecutionWorkout,
  storeFreeTextExecutionWorkout,
  type FreeTextExecutionWorkout,
} from "@/lib/free-text-execution";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import {
  buildFreeTextSegments,
  type FreeTextRun,
  type FreeTextTimerPreset,
  freeTextLimitMs,
  freeTextPosition,
  QUICK_PRESETS,
  readFreeTextRun,
  readLastPreset,
  runElapsedMs,
  storeFreeTextRun,
  storeLastPreset,
} from "@/lib/free-text-timer";
import { segmentLabel } from "@/lib/segment-label";
import { type CueMode, type CueSnapshot, nextCue, playCue, primeCueAudio, readCueMode } from "@/lib/timer-cues";
import { getFormatLabels, type SectionFormat } from "@/types/workout";
import { FreeTextTimerFields } from "../creation/FreeTextTimerFields";
import { CastView } from "./CastView";
import { FinishWizard } from "./FinishWizard";
import { displaySeconds, type TimerPhase, TimerDisplay } from "./TimerDisplay";

type TimerStatus = "setup" | "running" | "paused" | "finished";

const TICK_MS = 250;

export function FreeTextExecutionMode() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const workoutId = searchParams.get("workout");
  const executionId = searchParams.get("execution");
  const [workout, setWorkout] = useState<FreeTextExecutionWorkout | null>(() =>
    readFreeTextExecutionWorkout(workoutId),
  );
  const [showFinishWizard, setShowFinishWizard] = useState(false);
  const [isSavingCompletion, setIsSavingCompletion] = useState(false);
  const [completionFeedback, setCompletionFeedback] = useState<string | null>(null);
  const [initialModifications, setInitialModifications] = useState<ExerciseModification[]>([]);
  const [cueMode] = useState<CueMode>(() => readCueMode());
  const [castMode, setCastMode] = useState(false);
  const exitCastMode = useCallback(() => setCastMode(false), []);
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);

  const runExecutionId = workout?.execution_id ?? null;
  const [run, setRun] = useState<FreeTextRun | null>(null);
  const [draftPreset, setDraftPreset] = useState<FreeTextTimerPreset>(
    () => workout?.timer_preset ?? readLastPreset() ?? { format: "for_time", duration_seconds: 720 },
  );

  // Resume the clock this execution was running before a reload (the
  // execution id can arrive after the first render, once it is recovered).
  const [runLoadedFor, setRunLoadedFor] = useState<string | null>(null);
  if (runExecutionId && runLoadedFor !== runExecutionId) {
    setRunLoadedFor(runExecutionId);
    setRun(readFreeTextRun(runExecutionId));
  }

  // The coach's preset arrives with the workout; use it until the athlete picks another.
  const coachPreset = workout?.timer_preset ?? null;
  const [seenCoachPreset, setSeenCoachPreset] = useState(coachPreset);
  if (coachPreset !== seenCoachPreset) {
    setSeenCoachPreset(coachPreset);
    if (coachPreset) setDraftPreset(coachPreset);
  }

  function updateRun(next: FreeTextRun | null) {
    setRun(next);
    if (runExecutionId) storeFreeTextRun(runExecutionId, next);
  }

  const running = run?.startedAt != null;
  const [now, setNow] = useState(() => Date.now());
  const segments = useMemo(() => buildFreeTextSegments(run?.preset ?? draftPreset), [draftPreset, run?.preset]);
  const position = freeTextPosition(segments, run ? runElapsedMs(run, Math.max(now, run.startedAt ?? 0)) : 0);
  // The run stops exactly at the end of its last segment: elapsed time is
  // capped there, so the clock simply stops ticking.
  const ticking = running && !position.finished;
  const runLimitMs = useMemo(() => freeTextLimitMs(segments), [segments]);
  useEffect(() => {
    if (!ticking) return;
    const tick = () => setNow(Date.now());
    tick();
    const interval = window.setInterval(tick, TICK_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") tick();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [ticking]);

  const status: TimerStatus = !run ? "setup" : position.finished ? "finished" : running ? "running" : "paused";
  const phase: TimerPhase = position.segment.phase === "rest" ? "rest" : "work";

  useScreenWakeLock(status === "running");

  const previousStatusRef = useRef(status);
  useEffect(() => {
    if (status === "finished" && previousStatusRef.current === "running") playCue("finish", cueMode);
    previousStatusRef.current = status;
  }, [cueMode, status]);

  const previousCueRef = useRef<CueSnapshot | null>(null);
  const cueKey = `${position.segment.segment_key}#${position.clock.window?.index ?? 0}`;
  const remainingSeconds = position.clock.remainingMs === null ? null : Math.ceil(position.clock.remainingMs / 1000);
  useEffect(() => {
    const snapshot: CueSnapshot = {
      segmentKey: cueKey,
      running: status === "running",
      remaining: remainingSeconds,
      phase: phase === "rest" ? "rest" : "work",
    };
    const cue = nextCue(previousCueRef.current, snapshot);
    previousCueRef.current = snapshot;
    if (cue) playCue(cue, cueMode);
  }, [cueKey, cueMode, phase, remainingSeconds, status]);

  function start() {
    primeCueAudio();
    storeLastPreset(draftPreset);
    updateRun({ preset: draftPreset, startedAt: Date.now(), carriedMs: 0 });
  }

  function pause() {
    if (!run || run.startedAt === null) return;
    const elapsed = runElapsedMs(run, Date.now());
    updateRun({ ...run, startedAt: null, carriedMs: runLimitMs === null ? elapsed : Math.min(elapsed, runLimitMs) });
  }

  function resume() {
    if (!run) return;
    primeCueAudio();
    updateRun({ ...run, startedAt: Date.now() });
  }

  function reset() {
    updateRun(null);
  }

  useEffect(() => {
    if (workout?.execution_id || !tokens?.access_token || !workoutId) return;

    const accessToken = tokens.access_token;
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    let cancelled = false;

    async function recoverWorkout() {
      try {
        const record = await fetchWorkout(accessToken, workoutId!);
        if (record.authoring_mode !== "free_text") {
          router.replace("/workouts");
          return;
        }

        const execution = executionId
          ? await fetchExecution(accessToken, executionId)
          : await startExecution(accessToken, {
              master_workout_id: record.id,
              source: "self_selected",
              timezone,
            });

        if (execution.master_workout_id !== record.id) {
          router.replace("/workouts");
          return;
        }

        if (cancelled) return;
        setInitialModifications(execution.exercise_modifications ?? []);
        storeFreeTextExecutionWorkout(record, execution);
        setWorkout(readFreeTextExecutionWorkout(workoutId));
      } catch {
        if (!cancelled) router.replace("/workouts");
      }
    }

    void recoverWorkout();

    return () => {
      cancelled = true;
    };
  }, [executionId, router, tokens?.access_token, workout?.execution_id, workoutId]);

  useEffect(() => {
    const activeExecutionId = workout?.execution_id;
    if (!tokens?.access_token || !activeExecutionId) return;

    let cancelled = false;
    void fetchExecution(tokens.access_token, activeExecutionId)
      .then((execution) => {
        if (!cancelled) setInitialModifications(execution.exercise_modifications ?? []);
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
    };
  }, [tokens?.access_token, workout?.execution_id]);

  function beginFinish() {
    pause();
    setCompletionFeedback(null);
    setShowFinishWizard(true);
  }

  async function confirmFinish(editedScores: SectionScore[], modifications: ExerciseModification[]) {
    if (!tokens?.access_token || !workout?.execution_id) {
      setCompletionFeedback(i18n("workoutCompletionCouldNotBeSavedTryAgaindce610c"));
      return;
    }

    setIsSavingCompletion(true);
    setCompletionFeedback(null);

    try {
      if (modifications.length > 0) {
        const updated = await addExecutionModifications(tokens.access_token, workout.execution_id, modifications);
        setInitialModifications(updated.exercise_modifications ?? modifications);
      }

      await completeExecutionRequest(tokens.access_token, workout.execution_id, {
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        checked_exercise_ids: [],
        section_scores: editedScores,
        total_elapsed_ms: Math.round(position.totalElapsedMs),
        section_elapsed_ms: {},
        segment_cycle_counts: {},
      });
      clearFreeTextExecutionWorkout(workout.id);
      storeFreeTextRun(workout.execution_id, null);
      router.push("/");
    } catch (error) {
      setCompletionFeedback(
        error instanceof Error ? error.message : i18n("workoutCompletionCouldNotBeSavedTryAgaindce610c"),
      );
    } finally {
      setIsSavingCompletion(false);
    }
  }

  if (!workout) {
    return (
      <div className="flex min-h-screen items-center justify-center px-6 text-sm" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {i18n("recoveringWorkoutSessionc78ae35")}
      </div>
    );
  }

  if (showFinishWizard) {
    return (
      <FinishWizard
        scores={[]}
        segments={[]}
        initialModifications={initialModifications}
        freeText
        isSaving={isSavingCompletion}
        feedback={completionFeedback}
        onConfirm={confirmFinish}
        onCancel={() => setShowFinishWizard(false)}
      />
    );
  }

  return (
    <div className="flex h-dvh flex-col overflow-hidden" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <header className="flex items-center justify-between gap-3 border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
        <button type="button" onClick={() => router.back()} className="rounded-xl px-3 py-2 text-sm" style={{ color: "var(--muted)" }}>
          {i18n("backdc381ae")}
        </button>
        <div className="min-w-0 text-center">
          <div className="truncate text-sm font-bold">{workout.title}</div>
          <div className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("authoringModeFreeText")}
          </div>
        </div>
        <button type="button" onClick={beginFinish} className="rounded-xl px-3 py-2 text-sm" style={{ color: "var(--primary)" }}>
          {i18n("donee9b450d")}
        </button>
      </header>

      <main className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[minmax(0,0.9fr)_minmax(20rem,0.7fr)]">
        <section className="min-h-0 overflow-auto border-e p-5" style={{ borderColor: "var(--border)" }}>
          <pre className="whitespace-pre-wrap font-sans text-base leading-7" style={{ color: "var(--text)" }}>
            {workout.body}
          </pre>
        </section>

        <section className="flex min-h-0 flex-col overflow-auto p-5">
          {status === "setup" ? (
            <TimerSetup
              preset={draftPreset}
              coachPreset={coachPreset}
              formatLabels={formatLabels}
              onChange={setDraftPreset}
            />
          ) : (
            <div className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
                {formatLabels[position.segment.format as SectionFormat] ?? position.segment.format}
              </span>
              <button
                type="button"
                onClick={() => setCastMode(true)}
                className="min-h-11 rounded-xl px-3 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("castModeLabel")}
              </button>
            </div>
          )}

          <div className="flex flex-1 flex-col items-center justify-center">
            <TimerDisplay
              segment={position.segment}
              clock={position.clock}
              phase={phase}
              running={status === "running"}
              roundsCompleted={null}
              roundTarget={null}
              targetReps={null}
              formatLabel={formatLabels[position.segment.format as SectionFormat] ?? position.segment.format}
            />
          </div>

          <div className="grid grid-cols-3 gap-3">
            <button
              type="button"
              onClick={reset}
              disabled={status === "setup"}
              className="min-h-14 rounded-full text-sm font-bold disabled:opacity-30"
              style={{ background: "var(--card)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {i18n("resetTimerLabel")}
            </button>
            {status === "running" ? (
              <button type="button" onClick={pause} className="col-span-2 min-h-14 rounded-full text-base font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {i18n("pausecd21a1b")}
              </button>
            ) : status === "finished" ? (
              <button type="button" onClick={beginFinish} className="col-span-2 min-h-14 rounded-full text-base font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {i18n("finishb74bdee")}
              </button>
            ) : (
              <button
                type="button"
                onClick={status === "paused" ? resume : start}
                className="col-span-2 min-h-14 rounded-full text-base font-bold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {status === "paused" ? i18n("resumeb3bd0b5") : i18n("startTimerLabel")}
              </button>
            )}
          </div>
        </section>
      </main>

      {castMode ? (
        <CastView
          seconds={displaySeconds(position.segment, position.clock).seconds}
          phase={phase}
          label={segmentLabel(position.segment, i18n) || workout.title}
          sectionName={workout.title}
          roundText={
            position.clock.window
              ? position.clock.window.count
                ? i18n("timerRoundLabel", { round: position.clock.window.index, rounds: position.clock.window.count })
                : i18n("intervalWindowLabel", { window: position.clock.window.index })
              : position.segment.round && position.segment.total_rounds
                ? i18n("timerRoundLabel", { round: position.segment.round, rounds: position.segment.total_rounds })
                : null
          }
          nextText={null}
          finalSeconds={status === "running" && remainingSeconds !== null && remainingSeconds > 0 && remainingSeconds <= 3}
          paused={status === "paused"}
          onExit={exitCastMode}
        />
      ) : null}
    </div>
  );
}

function TimerSetup({
  preset,
  coachPreset,
  formatLabels,
  onChange,
}: {
  preset: FreeTextTimerPreset;
  coachPreset: FreeTextTimerPreset | null;
  formatLabels: Record<SectionFormat, string>;
  onChange: (preset: FreeTextTimerPreset) => void;
}) {
  const i18n = useUiTranslations();
  const [lastUsed] = useState(() => readLastPreset());
  const same = (a: FreeTextTimerPreset | null) => a !== null && JSON.stringify(a) === JSON.stringify(preset);
  const chips: { id: string; label: string; preset: FreeTextTimerPreset }[] = [
    ...(coachPreset ? [{ id: "coach", label: i18n("coachTimerPresetLabel"), preset: coachPreset }] : []),
    ...(lastUsed && !same(coachPreset) ? [{ id: "last", label: i18n("lastUsedTimerLabel"), preset: lastUsed }] : []),
    ...QUICK_PRESETS.map((quick) => ({ id: quick.id, label: i18n(`timerPreset_${quick.id}`), preset: quick.preset })),
  ];

  return (
    <div className="rounded-2xl border p-4" style={{ background: "var(--panel)", borderColor: "var(--border)" }}>
      <div className="flex flex-wrap gap-2" role="group" aria-label={i18n("timerPresetsLabel")}>
        {chips.map((chip) => (
          <button
            key={chip.id}
            type="button"
            aria-pressed={same(chip.preset)}
            onClick={() => onChange(chip.preset)}
            className="min-h-10 rounded-full px-3 text-sm font-semibold"
            style={
              same(chip.preset)
                ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                : { border: "1px solid var(--border)", color: "var(--text-soft)" }
            }
          >
            {chip.label}
          </button>
        ))}
      </div>
      <FreeTextTimerFields preset={preset} formatLabels={formatLabels} onChange={onChange} />
    </div>
  );
}
