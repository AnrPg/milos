"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { fetchWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import {
  readFreeTextExecutionWorkout,
  storeFreeTextExecutionWorkout,
  type FreeTextExecutionWorkout,
} from "@/lib/free-text-execution";
import type { SectionFormat } from "@/types/workout";

const TIMER_FORMATS: SectionFormat[] = [
  "untimed",
  "for_time",
  "train_to_exhaustion",
  "kcal_target",
  "emom",
  "complex_emom",
  "even_odd",
  "billat",
  "amrap",
  "edt",
  "death_by",
  "tabata",
  "custom_hiit",
  "cluster",
  "hrr",
  "ladder_ascending",
  "ladder_descending",
  "pyramid",
  "rest",
];

type TimerStatus = "idle" | "running" | "paused" | "finished";

export function FreeTextExecutionMode() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const workoutId = searchParams.get("workout");
  const [workout, setWorkout] = useState<FreeTextExecutionWorkout | null>(() =>
    readFreeTextExecutionWorkout(workoutId),
  );
  const [format, setFormat] = useState<SectionFormat>("for_time");
  const [durationMinutes, setDurationMinutes] = useState(20);
  const [rounds, setRounds] = useState(8);
  const [workSeconds, setWorkSeconds] = useState(20);
  const [restSeconds, setRestSeconds] = useState(10);
  const [intervalSeconds, setIntervalSeconds] = useState(60);
  const [status, setStatus] = useState<TimerStatus>("idle");
  const [elapsedMs, setElapsedMs] = useState(0);
  const startedAtRef = useRef<number | null>(null);
  const carriedElapsedRef = useRef(0);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (workout || !tokens?.access_token || !workoutId) return;

    fetchWorkout(tokens.access_token, workoutId)
      .then((record) => {
        if (record.authoring_mode !== "free_text") {
          router.replace("/workouts");
          return;
        }
        storeFreeTextExecutionWorkout(record);
        setWorkout(readFreeTextExecutionWorkout(workoutId));
      })
      .catch(() => router.replace("/workouts"));
  }, [router, tokens?.access_token, workout, workoutId]);

  useEffect(() => {
    if (status !== "running") {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
      return;
    }

    startedAtRef.current = Date.now();
    const tick = () => {
      if (startedAtRef.current === null) return;
      const nextElapsed = carriedElapsedRef.current + (Date.now() - startedAtRef.current);
      setElapsedMs(nextElapsed);
      if (timerLimitSeconds(format, durationMinutes, rounds, workSeconds, restSeconds, intervalSeconds) !== null) {
        const limitMs =
          timerLimitSeconds(format, durationMinutes, rounds, workSeconds, restSeconds, intervalSeconds)! * 1000;
        if (nextElapsed >= limitMs) {
          carriedElapsedRef.current = limitMs;
          setElapsedMs(limitMs);
          setStatus("finished");
          return;
        }
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    };
  }, [durationMinutes, format, intervalSeconds, restSeconds, rounds, status, workSeconds]);

  const elapsedSeconds = Math.floor(elapsedMs / 1000);
  const limitSeconds = timerLimitSeconds(format, durationMinutes, rounds, workSeconds, restSeconds, intervalSeconds);
  const remainingSeconds = limitSeconds === null ? null : Math.max(0, limitSeconds - elapsedSeconds);
  const displaySeconds = displayCountsUp(format) ? elapsedSeconds : (remainingSeconds ?? elapsedSeconds);
  const phase = useMemo(
    () => phaseLabel(format, elapsedSeconds, rounds, workSeconds, restSeconds, intervalSeconds, i18n),
    [elapsedSeconds, format, i18n, intervalSeconds, restSeconds, rounds, workSeconds],
  );

  function start() {
    if (status === "finished") reset();
    setStatus("running");
  }

  function pause() {
    carriedElapsedRef.current = elapsedMs;
    startedAtRef.current = null;
    setStatus("paused");
  }

  function reset() {
    carriedElapsedRef.current = 0;
    startedAtRef.current = null;
    setElapsedMs(0);
    setStatus("idle");
  }

  if (!workout) {
    return (
      <div className="flex min-h-screen items-center justify-center px-6 text-sm" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {i18n("recoveringWorkoutSessionc78ae35")}
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden" style={{ background: "var(--bg)", color: "var(--text)" }}>
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
        <button type="button" onClick={() => router.push("/")} className="rounded-xl px-3 py-2 text-sm" style={{ color: "var(--primary)" }}>
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
          <div className="rounded-2xl border p-4" style={{ background: "var(--panel)", borderColor: "var(--border)" }}>
            <label className="block">
              <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                {i18n("timerFormatLabel")}
              </span>
              <select
                value={format}
                onChange={(event) => {
                  reset();
                  setFormat(event.target.value as SectionFormat);
                }}
                className="mt-2 w-full rounded-xl border px-3 py-2 text-sm"
                style={{ background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" }}
              >
                {TIMER_FORMATS.map((item) => (
                  <option key={item} value={item}>
                    {item.replaceAll("_", " ")}
                  </option>
                ))}
              </select>
            </label>

            {format !== "untimed" ? (
              <div className="mt-4 grid grid-cols-2 gap-3">
                {usesDuration(format) ? (
                  <NumberField label={i18n("durationMinutesLabel")} value={durationMinutes} min={1} onChange={setDurationMinutes} />
                ) : null}
                {usesRounds(format) ? (
                  <NumberField label={i18n("roundsLabel")} value={rounds} min={1} onChange={setRounds} />
                ) : null}
                {usesInterval(format) ? (
                  <NumberField label={i18n("intervalSecondsLabel")} value={intervalSeconds} min={5} onChange={setIntervalSeconds} />
                ) : null}
                {usesWorkRest(format) ? (
                  <>
                    <NumberField label={i18n("workSecondsLabel")} value={workSeconds} min={1} onChange={setWorkSeconds} />
                    <NumberField label={i18n("restSecondsLabel")} value={restSeconds} min={0} onChange={setRestSeconds} />
                  </>
                ) : null}
              </div>
            ) : null}
          </div>

          <div className="flex flex-1 flex-col items-center justify-center gap-4 py-8">
            <div className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--muted)" }}>
              {phase}
            </div>
            <div className="font-mono text-7xl font-bold tabular-nums leading-none md:text-8xl" style={{ color: status === "finished" ? "var(--danger)" : "var(--text)" }}>
              {formatTime(displaySeconds)}
            </div>
            {remainingSeconds !== null && displayCountsUp(format) ? (
              <div className="text-sm" style={{ color: "var(--dim)" }}>
                {i18n("remainingTimeLabel", { time: formatTime(remainingSeconds) })}
              </div>
            ) : null}
          </div>

          <div className="grid grid-cols-3 gap-3">
            <button type="button" onClick={reset} className="rounded-full py-3 text-sm font-bold" style={{ background: "var(--card)", color: "var(--text)" }}>
              {i18n("resetTimerLabel")}
            </button>
            {status === "running" ? (
              <button type="button" onClick={pause} className="col-span-2 rounded-full py-3 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {i18n("pausecd21a1b")}
              </button>
            ) : (
              <button type="button" onClick={start} className="col-span-2 rounded-full py-3 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {status === "paused" ? i18n("resumeb3bd0b5") : i18n("startTimerLabel")}
              </button>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}

function NumberField({
  label,
  value,
  min,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  onChange: (value: number) => void;
}) {
  return (
    <label className="block">
      <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>
        {label}
      </span>
      <input
        type="number"
        min={min}
        value={value}
        onChange={(event) => onChange(Math.max(min, Number(event.target.value) || min))}
        className="mt-1 w-full rounded-xl border px-3 py-2 text-sm"
        style={{ background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" }}
      />
    </label>
  );
}

function formatTime(totalSeconds: number) {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function displayCountsUp(format: SectionFormat) {
  return format === "for_time" || format === "train_to_exhaustion" || format === "kcal_target" || format === "hrr";
}

function usesDuration(format: SectionFormat) {
  return !["untimed", "tabata", "custom_hiit", "emom", "complex_emom", "even_odd"].includes(format);
}

function usesRounds(format: SectionFormat) {
  return ["tabata", "custom_hiit", "emom", "complex_emom", "even_odd", "billat", "death_by", "cluster"].includes(format);
}

function usesInterval(format: SectionFormat) {
  return ["emom", "complex_emom", "even_odd", "death_by", "cluster"].includes(format);
}

function usesWorkRest(format: SectionFormat) {
  return ["tabata", "custom_hiit", "billat"].includes(format);
}

function timerLimitSeconds(
  format: SectionFormat,
  durationMinutes: number,
  rounds: number,
  workSeconds: number,
  restSeconds: number,
  intervalSeconds: number,
) {
  if (format === "untimed") return null;
  if (usesInterval(format)) return rounds * intervalSeconds;
  if (usesWorkRest(format)) return rounds * (workSeconds + restSeconds);
  if (displayCountsUp(format)) return durationMinutes > 0 ? durationMinutes * 60 : null;
  return durationMinutes * 60;
}

function phaseLabel(
  format: SectionFormat,
  elapsedSeconds: number,
  rounds: number,
  workSeconds: number,
  restSeconds: number,
  intervalSeconds: number,
  i18n: ReturnType<typeof useUiTranslations>,
) {
  if (format === "untimed") return i18n("manual4e836fd");
  if (usesInterval(format)) {
    const currentRound = Math.min(rounds, Math.floor(elapsedSeconds / intervalSeconds) + 1);
    return i18n("timerRoundLabel", { round: currentRound, rounds });
  }
  if (usesWorkRest(format)) {
    const cycle = workSeconds + restSeconds;
    const currentRound = Math.min(rounds, Math.floor(elapsedSeconds / cycle) + 1);
    const inCycle = elapsedSeconds % cycle;
    const phase = inCycle < workSeconds ? i18n("workPhaseLabel") : i18n("restPhaseLabel");
    return `${phase} · ${i18n("timerRoundLabel", { round: currentRound, rounds })}`;
  }
  return format.replaceAll("_", " ");
}
