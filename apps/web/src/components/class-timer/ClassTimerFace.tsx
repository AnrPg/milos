"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { useMemo } from "react";

import type { ClassTimerPayload } from "@/api/class-timers";
import { displaySeconds, formatClock, PHASE_COLORS, type TimerPhase } from "@/components/workouts/execution/TimerDisplay";
import type { ClassTimerPosition } from "@/lib/class-timer";
import { segmentLabel } from "@/lib/segment-label";
import { getFormatLabels, type SectionFormat } from "@/types/workout";

export function phaseOf(position: ClassTimerPosition | null): TimerPhase {
  const phase = position?.segment?.phase;
  return phase === "rest" || phase === "transition" ? phase : "work";
}

/** "Round 3/8", "Interval 4" or null, for the current segment. */
export function useRoundText(position: ClassTimerPosition | null) {
  const i18n = useUiTranslations();
  const window = position?.clock?.window ?? null;
  const segment = position?.segment ?? null;
  if (window) {
    return window.count
      ? i18n("timerRoundLabel", { round: window.index, rounds: window.count })
      : i18n("intervalWindowLabel", { window: window.index });
  }
  if (segment?.round && segment.total_rounds) {
    return i18n("timerRoundLabel", { round: segment.round, rounds: segment.total_rounds });
  }
  return null;
}

type Props = {
  payload: ClassTimerPayload;
  position: ClassTimerPosition | null;
  /** Wall display: fill the screen and size type to the viewport. */
  size: "wall" | "panel";
};

/** The clock everyone in the room reads: phase, time, round and what's next. */
export function ClassTimerFace({ payload, position, size }: Props) {
  const i18n = useUiTranslations();
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);
  const roundText = useRoundText(position);
  const wall = size === "wall";
  const phase = phaseOf(position);
  const color = PHASE_COLORS[phase];
  const segment = position?.segment ?? null;
  const next = position ? payload.segments[position.index + 1] ?? null : null;
  const getReady = position && position.startsInMs > 0 ? Math.ceil(position.startsInMs / 1000) : null;
  const clock = segment && position?.clock ? displaySeconds(segment, position.clock) : null;
  const finalSeconds =
    position?.status === "running" && getReady === null && clock?.countsDown && clock.seconds > 0 && clock.seconds <= 3;

  const statusText =
    position?.status === "ready"
      ? i18n("classTimerReady")
      : position?.status === "paused"
        ? i18n("pausedc7dfb6f")
        : position?.status === "finished"
          ? i18n("classTimerFinished")
          : getReady !== null
            ? i18n("getReadyLabel")
            : phase === "rest"
              ? i18n("restPhaseLabel")
              : phase === "transition"
                ? i18n("transitionPhaseLabel")
                : i18n("workPhaseLabel");

  const sectionText = segment
    ? [segment.section_name || formatLabels[segment.format as SectionFormat] || segment.format, segmentLabel(segment, i18n)]
        .filter((part, index, parts) => part && parts.indexOf(part) === index)
        .join(" · ")
    : null;

  return (
    <div
      className={`flex flex-col items-center justify-center text-center ${wall ? "gap-[2vmin]" : "gap-2"}`}
      style={{ color: "var(--text)" }}
    >
      <div
        className="font-bold uppercase tracking-widest"
        style={{ color: position?.status === "running" ? color : "var(--text-soft)", fontSize: wall ? "clamp(1.25rem, 5vmin, 4.5rem)" : "1rem" }}
      >
        {statusText}
      </div>

      <div
        role="timer"
        aria-live="off"
        className={`font-mono font-bold tabular-nums leading-none ${finalSeconds ? "motion-safe:animate-pulse" : ""}`}
        style={{
          fontSize: wall
            ? (clock?.seconds ?? 0) >= 3600
              ? "min(22vw, 44vh)"
              : "min(30vw, 56vh)"
            : "clamp(3.5rem, 16vw, 6rem)",
        }}
      >
        {getReady !== null ? getReady : clock ? formatClock(clock.seconds) : "—"}
      </div>

      {sectionText ? (
        <div className="max-w-[92vw] truncate font-semibold" style={{ color: "var(--text-soft)", fontSize: wall ? "clamp(1rem, 4.2vmin, 3.5rem)" : "1rem" }}>
          {sectionText}
        </div>
      ) : null}

      {roundText ? (
        <div className="font-bold tabular-nums" style={{ fontSize: wall ? "clamp(1rem, 4.5vmin, 3.75rem)" : "1rem" }}>
          {roundText}
        </div>
      ) : null}

      {next && position?.status !== "finished" ? (
        <div className="max-w-[92vw] truncate" style={{ color: "var(--muted)", fontSize: wall ? "clamp(0.9rem, 3vmin, 2.25rem)" : "0.875rem" }}>
          {i18n("nextUpLabel", {
            label:
              next.section_id !== segment?.section_id && !next.between_sections
                ? `${next.section_name} · ${segmentLabel(next, i18n)}`
                : segmentLabel(next, i18n),
          })}
          {next.kind === "countdown" && next.duration_seconds ? ` · ${formatClock(next.duration_seconds)}` : ""}
        </div>
      ) : null}
    </div>
  );
}

/** Exercise lines of the current segment, for the wall's side column. */
export function SegmentExercises({ position }: { position: ClassTimerPosition | null }) {
  const exercises = (position?.segment?.exercises ?? []).filter(
    (exercise) => !exercise.excluded && exercise.item_type !== "header",
  );
  if (exercises.length === 0) return null;

  return (
    <ul className="space-y-[1.5vmin]" style={{ fontSize: "clamp(1rem, 3.4vmin, 2.75rem)" }}>
      {exercises.map((exercise) => (
        <li key={exercise.id} className="font-semibold leading-tight">
          {exercise.prescription_value ? (
            <span className="tabular-nums" style={{ color: "var(--primary)" }}>
              {exercise.prescription_value}
              {exercise.prescription_unit && exercise.prescription_unit !== "reps" ? ` ${exercise.prescription_unit}` : ""}{" "}
            </span>
          ) : null}
          {exercise.name}
          {exercise.load_value ? <span style={{ color: "var(--muted)" }}> · {exercise.load_value}</span> : null}
        </li>
      ))}
    </ul>
  );
}
