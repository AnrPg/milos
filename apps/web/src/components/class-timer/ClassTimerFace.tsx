"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { useMemo } from "react";

import type { ClassTimerPayload } from "@/api/class-timers";
import { displaySeconds, formatClock, PHASE_COLORS, type TimerPhase } from "@/components/workouts/execution/TimerDisplay";
import type { ClassTimerPosition } from "@/lib/class-timer";
import { segmentLabel } from "@/lib/segment-label";
import { windowRound } from "@/lib/timer-now";
import { getFormatLabels, type SectionFormat } from "@/types/workout";

export function phaseOf(position: ClassTimerPosition | null): TimerPhase {
  const phase = position?.segment?.phase;
  if (phase === "rest" || phase === "transition") return phase;
  // A plan's intervals run work and rest as windows of one segment.
  return windowRound(position?.segment ?? null, position?.clock?.window ?? null)?.rest ? "rest" : "work";
}

/** "Round 3/8", "Interval 4" or null, for the current segment. */
export function useRoundText(position: ClassTimerPosition | null) {
  const i18n = useUiTranslations();
  const segment = position?.segment ?? null;
  const window = windowRound(segment, position?.clock?.window ?? null);
  if (window) {
    return window.rounds
      ? i18n("timerRoundLabel", { round: window.round, rounds: window.rounds })
      : i18n("intervalWindowLabel", { window: window.round });
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

  const face = (
    <div
      className={`flex flex-col items-center justify-center text-center ${wall ? "h-full gap-[2.4cqmin]" : "gap-2"}`}
      style={{ color: "var(--text)" }}
    >
      <div
        className="font-bold uppercase tracking-widest"
        style={{ color: position?.status === "running" ? color : "var(--text-soft)", fontSize: wall ? "clamp(1.25rem, 7cqmin, 4.5rem)" : "1rem" }}
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
              ? "min(16cqw, 40cqh)"
              : "min(36cqw, 50cqh)"
            : "clamp(3.5rem, 16vw, 6rem)",
        }}
      >
        {getReady !== null ? getReady : clock ? formatClock(clock.seconds) : "—"}
      </div>

      {sectionText ? (
        <div className="max-w-full truncate font-semibold" style={{ color: "var(--text-soft)", fontSize: wall ? "clamp(1rem, 5.5cqmin, 3.5rem)" : "1rem" }}>
          {sectionText}
        </div>
      ) : null}

      {roundText ? (
        <div className="font-bold tabular-nums" style={{ fontSize: wall ? "clamp(1rem, 6cqmin, 3.75rem)" : "1rem" }}>
          {roundText}
        </div>
      ) : null}

      {next && position?.status !== "finished" ? (
        <div className="max-w-full truncate" style={{ color: "var(--muted)", fontSize: wall ? "clamp(0.9rem, 4cqmin, 2.25rem)" : "0.875rem" }}>
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

  // The wall face sizes its type to the space it is given (whole screen, or beside «Τώρα»).
  return wall ? (
    <div className="h-full min-h-0 w-full min-w-0" style={{ containerType: "size" }}>
      {face}
    </div>
  ) : (
    face
  );
}
