"use client";

/**
 * ADR-270: running one section of a structured plan. Shows the current step
 * big, with the values of its set or round, what comes next and the flow's
 * clock (count-up for For Time with its cap, count-down per slot / interval
 * / window for EMOM, intervals and AMRAP). The athlete moves on with Space or
 * Enter (back with Backspace), may log what they actually did, and confirms
 * the section's score at the end in the shared `ScoreModal`.
 */
import { useTranslations } from "next-intl";
import React, { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";

import type { SectionScore } from "@/api/executions";
import { tempoShort } from "@/lib/structured-plan/parse";
import type { PlanFlow, PlanSection } from "@/lib/structured-plan/types";

import { ScoreModal } from "../ScoreModal";
import { formatClock, PHASE_COLORS, type TimerPhase } from "../TimerDisplay";
import {
  currentStep,
  initialRunState,
  phaseRemainingMs,
  type RunAction,
  runReducer,
  type RunState,
  upcomingStep,
} from "./runner";
import { measuredScore, type RunLogs, scoreSegment, type StepLog } from "./score";
import { buildSequence, type RunRest, type RunSequence, type RunStep, type RunWork } from "./sequence";

const TICK_MS = 250;

/** One value the athlete logged that differs from the target. */
export type PlanRunLog = { step: RunWork; field: "reps" | "load"; actual: string; canonical: string };

export type PlanRunResult = { score: SectionScore | null; elapsedMs: number };

type Props = {
  section: PlanSection;
  sectionId: string;
  sectionName: string;
  existingScore?: SectionScore;
  /** Called once, after the score is confirmed (or there is none). */
  onComplete: (result: PlanRunResult) => void;
  /** Called when the athlete moves past a step with logged values that differ from the target. */
  onLog?: (log: PlanRunLog) => void;
};

type Translate = ReturnType<typeof useTranslations>;

const MEASURE_KEYS = ["pace", "rpe", "rir", "zone", "height", "dist", "hold"] as const;

function isTyping(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(target.closest("input,textarea,select,button,a,[contenteditable=true],[role=dialog]"));
}

/** "Set 2 of 4", "Round 3", "Interval 5 of 8", for the step's own set / round. */
function roundLabel(t: Translate, flow: PlanFlow, step: RunStep, seq: RunSequence): string | null {
  if (step.kind !== "work" || step.interrupt) return null;
  const total = step.rounds;
  const key = flow === "sets" ? "set" : flow === "emom" || flow === "intervals" ? "interval" : "round";
  if (flow === "for_time" && total === 1) return null;
  if (total == null || (flow === "amrap" && seq.open)) return t(`${key}Open`, { n: step.round });
  return t(key, { n: step.round, total });
}

function phaseLabel(t: Translate, seq: RunSequence, state: RunState): string | null {
  const phase = seq.phases[state.phase];
  if (!phase || phase.round == null) return null;
  const windows = seq.phases.filter((p) => p.kind === "work").length;
  if (seq.flow === "amrap") return phase.kind === "work" ? t("window", { n: phase.round, total: windows }) : t("rest");
  return null;
}

function partLabel(t: Translate, step: RunWork): string | null {
  const { part, group } = step;
  if (part?.kind === "cluster") return t("cluster", { n: part.index + 1, count: part.count });
  if (part?.kind === "restpause") return t("restpause", { n: part.index + 1, count: part.count });
  if (part?.kind === "drop") {
    return part.index > 0 && part.by ? t("dropBy", { n: part.index, by: part.by }) : t("dropFirst");
  }
  if (group) return t(group.kind, { n: group.index + 1, size: group.size });
  return null;
}

function StepSummary({ step, t }: { step: RunStep; t: Translate }) {
  if (step.kind === "rest") return <span>{restText(t, step)}</span>;
  return (
    <span>
      <span className="font-semibold">{step.name || t("exercise")}</span>
      {step.values.dose ? <span> · {step.values.dose}</span> : null}
      {step.values.load ? <span> · {step.values.load}</span> : null}
    </span>
  );
}

function restText(t: Translate, rest: RunRest): string {
  if (rest.untilHr != null) return t("restUntilHr", { bpm: rest.untilHr });
  if (rest.range) return t("restRange", { from: formatClock(rest.range[0]), to: formatClock(rest.range[1]) });
  if (rest.secs != null) return t("restFor", { time: formatClock(rest.secs) });
  return rest.text ? t("restFor", { time: rest.text }) : t("rest");
}

export function PlanExecution({ section, sectionId, sectionName, existingScore, onComplete, onLog }: Props) {
  const t = useTranslations("PlanRun");
  const words = useMemo(
    () => ({ perSide: t("show.perSide"), within: t("show.within"), from: t("show.from"), zone: t("show.zone") }),
    [t],
  );
  const seq = useMemo(() => buildSequence(section, words), [section, words]);
  const reducer = useCallback((s: RunState, a: RunAction) => runReducer(seq, s, a), [seq]);
  const [state, dispatch] = useReducer(reducer, undefined, initialRunState);
  const [logs, setLogs] = useState<RunLogs>({});
  const [scoreOpen, setScoreOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  // The clock: running time is what was carried over plus the time since the last start / resume.
  const clockRef = useRef<{ startedAt: number | null; carriedMs: number }>({ startedAt: null, carriedMs: 0 });
  const running = state.status === "running";
  useEffect(() => {
    if (!running) return;
    clockRef.current.startedAt = Date.now();
    const tick = () => {
      const { startedAt, carriedMs } = clockRef.current;
      if (startedAt != null) dispatch({ type: "tick", elapsedMs: carriedMs + Date.now() - startedAt });
    };
    const interval = window.setInterval(tick, TICK_MS);
    return () => {
      window.clearInterval(interval);
      const { startedAt, carriedMs } = clockRef.current;
      if (startedAt != null) clockRef.current = { startedAt: null, carriedMs: carriedMs + Date.now() - startedAt };
    };
  }, [running]);

  const step = currentStep(seq, state);
  const upcoming = upcomingStep(seq, state);
  const phase = seq.phases[state.phase];
  const scoreLabel = section.score ? t(`score.${section.score}`) : "";
  const segment = useMemo(
    () => (section.score ? scoreSegment(sectionId, sectionName, section.score, scoreLabel) : null),
    [scoreLabel, section.score, sectionId, sectionName],
  );
  const done = state.status === "done";

  // Open the score as soon as the section ends.
  const [scoreAsked, setScoreAsked] = useState(false);
  if (done && !scoreAsked) {
    setScoreAsked(true);
    if (segment) setScoreOpen(true);
  }

  useEffect(() => {
    rootRef.current?.focus();
  }, []);

  /** Reports what the athlete logged on the step they are leaving. */
  const flushLog = useCallback(
    (leaving: RunStep | null) => {
      if (!onLog || leaving?.kind !== "work") return;
      const log = logs[leaving.key];
      if (!log) return;
      const pairs: Array<["reps" | "load", string | undefined, string]> = [
        ["reps", log.reps, leaving.values.dose],
        ["load", log.load, leaving.values.load],
      ];
      for (const [field, actual, canonical] of pairs) {
        const value = actual?.trim();
        if (value && value !== canonical.trim()) onLog({ step: leaving, field, actual: value, canonical });
      }
    },
    [logs, onLog],
  );

  const next = useCallback(() => {
    if (state.status === "ready") {
      dispatch({ type: "start" });
      return;
    }
    if (state.status !== "running") return;
    flushLog(step);
    dispatch({ type: "next" });
  }, [flushLog, state.status, step]);

  const prev = useCallback(() => dispatch({ type: "prev" }), []);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || scoreOpen) return;
      if (isTyping(event.target)) return;
      if (event.key === " " || event.key === "Enter") {
        event.preventDefault();
        next();
      } else if (event.key === "Backspace") {
        event.preventDefault();
        prev();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [next, prev, scoreOpen]);

  function setLog(key: string, change: StepLog) {
    setLogs((current) => ({ ...current, [key]: { ...current[key], ...change } }));
  }

  function complete(score: SectionScore | null) {
    setScoreOpen(false);
    onComplete({ score, elapsedMs: state.finishedAtMs ?? state.elapsedMs });
  }

  // ── clock ──────────────────────────────────────────────────────────────
  const remaining = phaseRemainingMs(seq, state);
  const phaseKind: TimerPhase = phase?.kind === "rest" || step?.kind === "rest" ? "rest" : "work";
  const color = state.interrupt ? "var(--warning)" : PHASE_COLORS[phaseKind];
  let clockSeconds: number;
  if (seq.clock === "down" && remaining != null) clockSeconds = Math.ceil(remaining / 1000);
  else if (seq.clock === "down") clockSeconds = Math.floor((state.elapsedMs - state.phaseStartMs) / 1000);
  else clockSeconds = Math.floor(state.elapsedMs / 1000);

  // A timed rest inside the work counts down on its own.
  const restLeft =
    step?.kind === "rest" && step.secs != null && phase?.kind === "work"
      ? Math.max(0, Math.ceil((step.secs * 1000 - (state.elapsedMs - (state.interrupt?.stepStartMs ?? state.stepStartMs))) / 1000))
      : null;
  const restSince =
    step?.kind === "rest" && step.secs == null ? Math.floor((state.elapsedMs - (state.interrupt?.stepStartMs ?? state.stepStartMs)) / 1000) : null;

  const nextLabel =
    state.status === "ready"
      ? t("start")
      : step?.kind === "rest" && step.untilHr != null
        ? t("hrReached")
        : step?.kind === "rest"
          ? t("skipRest")
          : !upcoming && !(phase && phase.secs != null && seq.flow !== "for_time")
            ? t("finish")
            : t("next");
  const waiting = state.status !== "ready" && !done && !step;
  const restPhase = phase?.kind === "rest" && phase.secs != null;
  const nextDisabled = done || waiting || restPhase || state.status === "paused";
  const measured = done && section.score ? measuredScore(seq, state, section.score, logs) : null;

  return (
    <div
      ref={rootRef}
      tabIndex={-1}
      data-testid="plan-run"
      className="flex min-h-0 flex-1 flex-col gap-4 px-4 pb-4 pt-3 outline-none"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t(`flow.${seq.flow}`)}
          </div>
          <div className="truncate text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {[sectionName, phaseLabel(t, seq, state)].filter(Boolean).join(" · ")}
          </div>
        </div>
        <div className="text-end">
          <div
            role="timer"
            aria-label={t("clock")}
            className="font-mono text-4xl font-bold tabular-nums leading-none"
            style={{ color: seq.clock === "none" ? "var(--muted)" : color }}
          >
            {formatClock(clockSeconds)}
          </div>
          {seq.capSecs != null ? (
            <div className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
              {t("cap", { time: formatClock(seq.capSecs) })}
            </div>
          ) : null}
        </div>
      </div>

      <section
        aria-live="polite"
        className="flex flex-1 flex-col justify-center gap-3 rounded-3xl p-5"
        style={{ background: "var(--panel)", border: `2px solid ${done ? "var(--border)" : color}` }}
      >
        {state.interrupt ? (
          <div className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--warning)" }}>
            {t("interrupt")}
          </div>
        ) : null}
        {done ? (
          <DoneView t={t} timeUp={state.timeUp} measured={measured} scoreLabel={segment ? scoreLabel : null} />
        ) : state.status === "ready" ? (
          <div className="flex flex-col gap-2">
            <div className="text-2xl font-bold">{t("ready")}</div>
            {step ? (
              <div className="text-base" style={{ color: "var(--text-soft)" }}>
                {t("firstUp")} <StepSummary step={step} t={t} />
              </div>
            ) : null}
          </div>
        ) : waiting ? (
          <div className="flex flex-col gap-2">
            <div className="text-2xl font-bold">{t("waiting")}</div>
            {remaining != null ? (
              <div className="text-base" style={{ color: "var(--text-soft)" }}>
                {t("nextStartsIn", { time: formatClock(Math.ceil(remaining / 1000)) })}
              </div>
            ) : null}
          </div>
        ) : step?.kind === "rest" ? (
          <div className="flex flex-col gap-2">
            <div className="text-3xl font-bold">{restText(t, step)}</div>
            {restLeft != null ? (
              <div className="font-mono text-6xl font-bold tabular-nums" style={{ color: PHASE_COLORS.rest }}>
                {formatClock(restLeft)}
              </div>
            ) : restSince != null && !restPhase ? (
              <div className="font-mono text-5xl font-bold tabular-nums" style={{ color: "var(--muted)" }}>
                {formatClock(restSince)}
              </div>
            ) : null}
          </div>
        ) : step?.kind === "work" ? (
          <WorkView t={t} step={step} seq={seq} log={logs[step.key]} onLog={(change) => setLog(step.key, change)} />
        ) : null}
      </section>

      {!done && upcoming && state.status !== "ready" ? (
        <div className="rounded-2xl px-4 py-3 text-sm" style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          <span className="me-2 text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
            {state.interrupt && !seq.interrupt?.steps[state.interrupt.step + 1] ? t("thenBack") : t("upNext")}
          </span>
          <StepSummary step={upcoming} t={t} />
        </div>
      ) : null}

      {done ? (
        <button
          type="button"
          onClick={() => (segment ? setScoreOpen(true) : complete(null))}
          className="w-full rounded-2xl py-4 text-lg font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {segment ? t("enterScore") : t("continue")}
        </button>
      ) : (
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={prev}
            disabled={state.status === "ready"}
            aria-label={t("previous")}
            className="min-h-14 rounded-2xl px-4 text-sm font-semibold disabled:opacity-40"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            ←
          </button>
          {state.status !== "ready" ? (
            <button
              type="button"
              onClick={() => dispatch({ type: state.status === "paused" ? "resume" : "pause" })}
              className="min-h-14 rounded-2xl px-4 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {state.status === "paused" ? t("resume") : t("pause")}
            </button>
          ) : null}
          <button
            type="button"
            data-testid="plan-run-next"
            onClick={next}
            disabled={nextDisabled}
            className="min-h-14 flex-1 rounded-2xl px-4 text-lg font-bold disabled:opacity-40"
            style={{ background: color, color: "var(--primary-contrast)" }}
          >
            {nextLabel}
          </button>
        </div>
      )}

      {!done && state.status !== "ready" ? (
        <div className="flex items-center justify-between gap-3 text-xs" style={{ color: "var(--dim)" }}>
          <span className="hidden sm:inline">{t("keys")}</span>
          <button type="button" onClick={() => dispatch({ type: "finish" })} className="ms-auto underline" style={{ color: "var(--muted)" }}>
            {t("endSection")}
          </button>
        </div>
      ) : null}

      {scoreOpen && segment ? (
        <ScoreModal
          segment={segment}
          existingScore={existingScore ?? (measured ? { section_id: sectionId, value: measured } : undefined)}
          onSave={(score) =>
            complete({ ...score, section_name: sectionName, score_type: segment.score_config?.type, source: "user", kind: "final" })
          }
          onClose={() => setScoreOpen(false)}
        />
      ) : null}
    </div>
  );
}

function WorkView({
  t,
  step,
  seq,
  log,
  onLog,
}: {
  t: Translate;
  step: RunWork;
  seq: RunSequence;
  log: StepLog | undefined;
  onLog: (change: StepLog) => void;
}) {
  const { values } = step;
  const tempo = values.tempo ? (tempoShort(values.tempo) ?? values.tempo) : "";
  const tags = [roundLabel(t, seq.flow, step, seq), partLabel(t, step), step.optional ? t("optional") : null].filter(
    (x): x is string => Boolean(x),
  );
  return (
    <div className="flex flex-col gap-3">
      {tags.length ? (
        <div className="flex flex-wrap gap-2">
          {tags.map((tag) => (
            <span
              key={tag}
              className="rounded-full px-3 py-1 text-xs font-semibold"
              style={{ background: "var(--muted-bg, var(--panel-muted))", color: "var(--text-soft)" }}
            >
              {tag}
            </span>
          ))}
        </div>
      ) : null}
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h2 className="break-words text-3xl font-bold leading-tight sm:text-4xl">{step.name || t("exercise")}</h2>
        {values.perSide ? (
          <span className="rounded-full px-2 py-0.5 text-xs font-semibold" style={{ border: "1px solid var(--border)", color: "var(--muted)" }}>
            {t("perSide")}
          </span>
        ) : null}
      </div>
      <dl className="flex flex-wrap gap-x-6 gap-y-2">
        {values.dose ? <Value label={t("reps")} value={values.dose} big /> : null}
        {values.load ? <Value label={t("load")} value={values.load} big /> : null}
        {tempo ? <Value label={t("measure.tempo")} value={tempo} /> : null}
        {MEASURE_KEYS.map((k) => (values.measures[k] ? <Value key={k} label={t(`measure.${k}`)} value={values.measures[k]!} /> : null))}
      </dl>
      {step.note ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {step.note}
        </p>
      ) : null}
      <fieldset className="flex flex-wrap gap-3 pt-1">
        <legend className="mb-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("logTitle")}
        </legend>
        <LogField label={t("logReps")} value={log?.reps ?? ""} placeholder={values.dose} inputMode="numeric" onChange={(reps) => onLog({ reps })} />
        {values.load ? (
          <LogField label={t("logLoad")} value={log?.load ?? ""} placeholder={values.load} inputMode="decimal" onChange={(load) => onLog({ load })} />
        ) : null}
      </fieldset>
    </div>
  );
}

function Value({ label, value, big = false }: { label: string; value: string; big?: boolean }) {
  return (
    <div className="flex flex-col">
      <dt className="text-xs" style={{ color: "var(--dim)" }}>
        {label}
      </dt>
      <dd className={big ? "text-3xl font-bold tabular-nums" : "text-lg font-semibold tabular-nums"}>{value}</dd>
    </div>
  );
}

function LogField({
  label,
  value,
  placeholder,
  inputMode,
  onChange,
}: {
  label: string;
  value: string;
  placeholder: string;
  inputMode: "numeric" | "decimal";
  onChange: (value: string) => void;
}) {
  return (
    <label className="flex min-w-0 flex-1 basis-32 flex-col gap-1 text-xs" style={{ color: "var(--muted)" }}>
      {label}
      <input
        type="text"
        inputMode={inputMode}
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        className="w-full rounded-xl px-3 py-2 text-base outline-none focus:ring-2"
        style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
    </label>
  );
}

function DoneView({ t, timeUp, measured, scoreLabel }: { t: Translate; timeUp: boolean; measured: string | null; scoreLabel: string | null }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="text-3xl font-bold">{timeUp ? t("timeUp") : t("done")}</div>
      {scoreLabel && measured ? (
        <div className="text-lg" style={{ color: "var(--text-soft)" }}>
          {scoreLabel}: <span className="font-bold tabular-nums">{measured}</span>
        </div>
      ) : null}
    </div>
  );
}
