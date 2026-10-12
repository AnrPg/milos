"use client";

import { useEffect, useState } from "react";

import type { TimerSegment } from "@/api/executions";
import { liveElapsedMs, readSegmentClock, type SegmentClock } from "@/lib/timer-engine";

export type TimerState = {
  /** Whole seconds elapsed in the segment. */
  elapsed: number;
  elapsedMs: number;
  /** Whole seconds left (countdown, cap or current window); null when untimed. */
  remaining: number | null;
  isExpired: boolean;
  clock: SegmentClock | null;
};

const TICK_MS = 250;

/**
 * Reads the current segment's clock. Time is always derived from the
 * segment's scheduled start and banked pause time (see `timer-engine`), so a
 * slow or skipped tick only delays the display — it can never make the timer
 * drift or report a stale segment as expired.
 *
 * Ticks use an interval rather than requestAnimationFrame, which browsers stop
 * entirely in background tabs; returning to the page re-reads the clock at
 * once so expired segments are caught up immediately.
 */
export function useWorkoutTimer(
  segment: TimerSegment | null,
  isActive: boolean,
  pausedElapsed: number,
  segmentStartedAt: number | null,
): TimerState {
  const running = Boolean(segment) && isActive;
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!running) return;

    const tick = () => setNow(Date.now());
    const interval = window.setInterval(tick, TICK_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") tick();
    };

    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", tick);

    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", tick);
    };
  }, [running]);

  // `now` only ever lags real time, so a fresh segment starts at 0 instead of
  // inheriting the previous segment's elapsed time.
  const elapsedMs = liveElapsedMs({ pausedElapsed, segmentStartedAt, running, now });

  if (!segment) {
    return { elapsed: Math.floor(elapsedMs / 1000), elapsedMs, remaining: null, isExpired: false, clock: null };
  }

  const clock = readSegmentClock(segment, elapsedMs);
  return {
    elapsed: Math.floor(elapsedMs / 1000),
    elapsedMs,
    remaining: clock.remainingMs === null ? null : Math.ceil(clock.remainingMs / 1000),
    isExpired: clock.isExpired,
    clock,
  };
}
