"use client";

import { useUiTranslations } from "@/i18n/ui";
import React from "react";

import type { TimerSegment } from "@/api/executions";
import type { SegmentClock } from "@/lib/timer-engine";

export type TimerPhase = "work" | "rest" | "transition";

export const PHASE_COLORS: Record<TimerPhase, string> = {
  work: "var(--primary)",
  rest: "var(--info, var(--success))",
  transition: "var(--warning)",
};

type Props = {
  segment: TimerSegment;
  clock: SegmentClock | null;
  phase: TimerPhase;
  running: boolean;
  /** Completed rounds for round-counting segments; null otherwise. */
  roundsCompleted: number | null;
  roundTarget: number | null;
  onRemoveRound?: () => void;
  /** Reps each exercise targets in the current window (Death By). */
  targetReps: number | null;
  formatLabel: string;
};

export function formatClock(totalSeconds: number): string {
  const seconds = Math.max(0, totalSeconds);
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;

  if (h > 0) {
    return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }
  return `${m}:${String(s).padStart(2, "0")}`;
}

const RING_RADIUS = 46;
const RING_LENGTH = 2 * Math.PI * RING_RADIUS;
const MAX_PIPS = 12;

export function TimerDisplay({
  segment,
  clock,
  phase,
  running,
  roundsCompleted,
  roundTarget,
  onRemoveRound,
  targetReps,
  formatLabel,
}: Props) {
  const i18n = useUiTranslations();
  const color = PHASE_COLORS[phase];
  const countsDown = clock?.remainingMs !== null && clock?.remainingMs !== undefined && segment.kind !== "countup";
  const seconds = countsDown
    ? Math.ceil((clock?.remainingMs ?? 0) / 1000)
    : Math.floor((clock?.elapsedMs ?? 0) / 1000);
  const finalSeconds = running && countsDown && seconds > 0 && seconds <= 3;
  const isCapped = segment.kind === "countup" && clock?.limitMs != null;
  const phaseLabel =
    phase === "rest" ? i18n("restPhaseLabel") : phase === "transition" ? i18n("transitionPhaseLabel") : i18n("workPhaseLabel");
  // Ring shows time left for countdowns (drains) and time used toward a cap (fills).
  const ringFraction = clock?.progress == null ? null : countsDown ? 1 - clock.progress : clock.progress;

  return (
    <div className="flex flex-col items-center gap-2 py-3">
      <div className="flex flex-wrap items-center justify-center gap-2">
        <span
          className="rounded-full px-3 py-1 text-xs font-bold uppercase tracking-widest"
          style={{ background: `color-mix(in srgb, ${color} 22%, transparent)`, color: "var(--text)" }}
        >
          {phaseLabel}
        </span>
        <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
          {segment.label}
        </span>
      </div>

      <div className="relative flex items-center justify-center">
        {ringFraction !== null ? (
          <svg
            viewBox="0 0 100 100"
            className="absolute inset-0 h-full w-full -rotate-90"
            aria-hidden="true"
          >
            <circle cx="50" cy="50" r={RING_RADIUS} fill="none" stroke="var(--border)" strokeWidth="3" />
            <circle
              cx="50"
              cy="50"
              r={RING_RADIUS}
              fill="none"
              stroke={color}
              strokeWidth="3"
              strokeLinecap="round"
              strokeDasharray={RING_LENGTH}
              strokeDashoffset={RING_LENGTH * (1 - ringFraction)}
            />
          </svg>
        ) : null}
        <div
          role="timer"
          aria-live="off"
          className={`relative flex aspect-square items-center justify-center font-mono font-bold tabular-nums leading-none ${finalSeconds ? "motion-safe:animate-pulse" : ""}`}
          style={{
            width: "min(78vw, 42dvh, 26rem)",
            fontSize: seconds >= 3600 ? "clamp(3rem, min(15vw, 9dvh), 6rem)" : "clamp(4rem, min(22vw, 13dvh), 9rem)",
            color: clock?.isExpired && isCapped ? "var(--danger)" : "var(--text)",
          }}
        >
          {formatClock(seconds)}
        </div>
      </div>

      <RoundLine
        segment={segment}
        clock={clock}
        color={color}
        roundsCompleted={roundsCompleted}
        roundTarget={roundTarget}
        onRemoveRound={onRemoveRound}
        targetReps={targetReps}
      />

      <div className="text-xs" style={{ color: "var(--dim)" }}>
        {formatLabel}
        {isCapped ? ` ${i18n("capa8fba29")} ${formatClock(Math.round((clock?.limitMs ?? 0) / 1000))}` : ""}
      </div>
    </div>
  );
}

function RoundLine({
  segment,
  clock,
  color,
  roundsCompleted,
  roundTarget,
  onRemoveRound,
  targetReps,
}: Pick<Props, "segment" | "clock" | "roundsCompleted" | "roundTarget" | "onRemoveRound" | "targetReps"> & {
  color: string;
}) {
  const i18n = useUiTranslations();

  if (clock?.window) {
    const { index, count } = clock.window;
    return (
      <div className="flex flex-col items-center gap-1">
        <div className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {count ? i18n("timerRoundLabel", { round: index, rounds: count }) : i18n("intervalWindowLabel", { window: index })}
        </div>
        {targetReps !== null ? (
          <div className="text-sm font-semibold" style={{ color }}>
            {i18n("targetRepsLabel", { reps: targetReps })}
          </div>
        ) : null}
        {roundsCompleted !== null ? (
          <RoundsDone count={roundsCompleted} onRemoveRound={onRemoveRound} />
        ) : null}
      </div>
    );
  }

  if (roundsCompleted !== null) {
    const current = roundTarget ? Math.min(roundsCompleted + 1, roundTarget) : roundsCompleted + 1;
    return (
      <div className="flex flex-col items-center gap-1">
        <div className="text-2xl font-bold" style={{ color: "var(--text)" }}>
          {roundTarget
            ? i18n("timerRoundLabel", { round: current, rounds: roundTarget })
            : i18n("roundNumberLabel", { round: current })}
        </div>
        <RoundsDone count={roundsCompleted} onRemoveRound={onRemoveRound} />
      </div>
    );
  }

  if (segment.total_rounds !== null && segment.round !== null) {
    if (segment.total_rounds > MAX_PIPS) {
      return (
        <div className="text-base font-semibold" style={{ color: "var(--text-soft)" }}>
          {i18n("timerRoundLabel", { round: segment.round, rounds: segment.total_rounds })}
        </div>
      );
    }

    return (
      <div
        className="flex items-center gap-2"
        role="img"
        aria-label={i18n("timerRoundLabel", { round: segment.round, rounds: segment.total_rounds })}
      >
        {Array.from({ length: segment.total_rounds }, (_, i) => (
          <span
            key={i}
            className="h-2.5 w-2.5 rounded-full transition-colors"
            style={{
              background:
                i + 1 === segment.round ? color : i + 1 < segment.round! ? "var(--dim)" : "var(--border)",
            }}
          />
        ))}
      </div>
    );
  }

  return null;
}

function RoundsDone({ count, onRemoveRound }: { count: number; onRemoveRound?: () => void }) {
  const i18n = useUiTranslations();

  return (
    <div className="flex items-center gap-2 text-sm" style={{ color: "var(--muted)" }}>
      <span>{i18n("roundsDoneLabel", { count })}</span>
      {onRemoveRound && count > 0 ? (
        <button
          type="button"
          onClick={onRemoveRound}
          aria-label={i18n("removeRoundLabel")}
          className="flex h-11 min-w-11 items-center justify-center rounded-full px-3 font-bold"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          −1
        </button>
      ) : null}
    </div>
  );
}
