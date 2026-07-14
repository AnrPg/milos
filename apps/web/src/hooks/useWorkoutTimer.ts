"use client";

import { useEffect, useRef, useState } from "react";

import type { TimerSegment } from "@/api/executions";

export type TimerState = {
  elapsed: number;
  remaining: number | null;
  isExpired: boolean;
};

/**
 * Drives a single timer segment using requestAnimationFrame for accuracy (±100ms).
 * Wall-clock diff against startTime ensures no drift across frames.
 */
export function useWorkoutTimer(
  segment: TimerSegment | null,
  isActive: boolean,
  pausedElapsed: number,
  segmentStartedAt: number | null,
): TimerState {
  const [elapsed, setElapsed] = useState(pausedElapsed);
  const rafRef = useRef<number | null>(null);
  const startTimeRef = useRef<number | null>(null);

  useEffect(() => {
    if (!segment || !isActive) {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      startTimeRef.current = null;
      return;
    }

    startTimeRef.current = segmentStartedAt ?? Date.now();

    const tick = () => {
      if (startTimeRef.current === null) return;
      const now = Date.now();
      const totalElapsed = pausedElapsed + (now - startTimeRef.current);
      setElapsed(totalElapsed);
      rafRef.current = requestAnimationFrame(tick);
    };

    rafRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      startTimeRef.current = null;
    };
  }, [isActive, pausedElapsed, segment, segmentStartedAt]);

  const elapsedSeconds = Math.floor((isActive ? elapsed : pausedElapsed) / 1000);

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
