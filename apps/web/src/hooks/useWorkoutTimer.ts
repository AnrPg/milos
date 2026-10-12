"use client";

import { useEffect, useState } from "react";

import type { TimerSegment } from "@/api/executions";

export type TimerState = {
  elapsed: number;
  remaining: number | null;
  isExpired: boolean;
};

type Tick = { key: string; elapsedMs: number };

/**
 * Drives a single timer segment using requestAnimationFrame for accuracy (±100ms).
 * Wall-clock diff against startTime ensures no drift across frames.
 *
 * Each tick is tagged with the inputs it was measured for. A tick taken for a
 * previous segment (or before a pause/resume) is ignored, so the first render
 * after a segment change never reports the old segment's elapsed time — which
 * would otherwise make a shorter next segment look expired and skip it.
 */
export function useWorkoutTimer(
  segment: TimerSegment | null,
  isActive: boolean,
  pausedElapsed: number,
  segmentStartedAt: number | null,
): TimerState {
  const running = Boolean(segment) && isActive;
  const tickKey = `${segment?.segment_key ?? ""}|${running}|${pausedElapsed}|${segmentStartedAt ?? ""}`;
  const [tick, setTick] = useState<Tick | null>(null);

  useEffect(() => {
    if (!running) return;

    const startedAt = segmentStartedAt ?? Date.now();
    let frame: number | null = null;

    const loop = () => {
      setTick({ key: tickKey, elapsedMs: pausedElapsed + Math.max(0, Date.now() - startedAt) });
      frame = requestAnimationFrame(loop);
    };

    frame = requestAnimationFrame(loop);

    return () => {
      if (frame !== null) cancelAnimationFrame(frame);
    };
  }, [running, pausedElapsed, segmentStartedAt, tickKey]);

  const elapsedMs = running && tick?.key === tickKey ? tick.elapsedMs : pausedElapsed;
  const elapsedSeconds = Math.floor(elapsedMs / 1000);

  if (!segment || segment.kind === "no_timer" || segment.kind === "manual") {
    return { elapsed: elapsedSeconds, remaining: null, isExpired: false };
  }

  if (segment.kind === "countdown" && segment.duration_seconds !== null) {
    const remaining = Math.max(0, segment.duration_seconds - elapsedSeconds);
    return { elapsed: elapsedSeconds, remaining, isExpired: remaining === 0 };
  }

  // countup: optional time cap
  if (segment.kind === "countup") {
    const cap = segment.duration_seconds;
    const isExpired = cap !== null && elapsedSeconds >= cap;
    const remaining = cap !== null ? Math.max(0, cap - elapsedSeconds) : null;
    return { elapsed: elapsedSeconds, remaining, isExpired };
  }

  return { elapsed: elapsedSeconds, remaining: null, isExpired: false };
}
