import type { TimerSegment } from "@/api/executions";

/**
 * Pure timing rules for workout execution. Everything is derived from a
 * segment's scheduled start (`segmentStartedAt`), banked time from earlier
 * pauses (`pausedElapsed`) and "now", so the clock is identical after a reload,
 * in a background tab, or on another device — nothing depends on a ticking loop
 * having run.
 */

export type IntervalWindow = {
  /** 1-based window number. */
  index: number;
  /** Total windows, or null for an open-ended cycle. */
  count: number | null;
  elapsedMs: number;
  lengthMs: number;
};

export type SegmentClock = {
  elapsedMs: number;
  /** Countdown, cap or current-window remaining time; null for untimed segments. */
  remainingMs: number | null;
  /** When the segment ends on its own; null when only the athlete can end it. */
  limitMs: number | null;
  isExpired: boolean;
  /** 0..1 progress for the countdown ring; null when there is nothing to fill. */
  progress: number | null;
  window: IntervalWindow | null;
};

const positiveSeconds = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;

/** Window lengths of an interval cycle, cycling through an authored pattern. */
export function windowLengthsMs(segment: TimerSegment): number[] {
  const pattern = segment.timer_config?.interval_pattern_seconds;
  if (Array.isArray(pattern)) {
    const lengths = pattern.map(positiveSeconds).filter((value): value is number => value !== null);
    if (lengths.length > 0) return lengths.map((seconds) => seconds * 1000);
  }
  const duration = positiveSeconds(segment.duration_seconds);
  return duration ? [duration * 1000] : [];
}

export function segmentLimitMs(segment: TimerSegment): number | null {
  const duration = positiveSeconds(segment.duration_seconds);

  switch (segment.kind) {
    case "countdown":
    case "countup":
      return duration ? duration * 1000 : null;
    case "interval_cycle": {
      const lengths = windowLengthsMs(segment);
      const windows = segment.total_rounds;
      if (!windows || lengths.length === 0) return null;
      let total = 0;
      for (let window = 0; window < windows; window += 1) total += lengths[window % lengths.length]!;
      return total;
    }
    default:
      return null;
  }
}

export function intervalWindowAt(segment: TimerSegment, elapsedMs: number): IntervalWindow | null {
  const lengths = windowLengthsMs(segment);
  if (lengths.length === 0) return null;

  const cycleMs = lengths.reduce((sum, length) => sum + length, 0);
  const fullCycles = Math.floor(Math.max(0, elapsedMs) / cycleMs);
  let offset = Math.max(0, elapsedMs) - fullCycles * cycleMs;
  let index = fullCycles * lengths.length;

  for (const length of lengths) {
    index += 1;
    if (offset < length) return { index, count: segment.total_rounds, elapsedMs: offset, lengthMs: length };
    offset -= length;
  }

  // Unreachable: offset is always smaller than one full cycle.
  return { index, count: segment.total_rounds, elapsedMs: 0, lengthMs: lengths.at(-1)! };
}

export function readSegmentClock(segment: TimerSegment, elapsedMs: number): SegmentClock {
  const elapsed = Math.max(0, elapsedMs);
  const limitMs = segmentLimitMs(segment);
  const isExpired = limitMs !== null && elapsed >= limitMs;

  if (segment.kind === "interval_cycle") {
    const window = intervalWindowAt(segment, Math.min(elapsed, limitMs ?? elapsed));
    const remainingMs = isExpired || !window ? 0 : window.lengthMs - window.elapsedMs;
    return {
      elapsedMs: elapsed,
      remainingMs,
      limitMs,
      isExpired,
      progress: window ? Math.min(1, window.elapsedMs / window.lengthMs) : null,
      window,
    };
  }

  if (limitMs === null) {
    return { elapsedMs: elapsed, remainingMs: null, limitMs, isExpired: false, progress: null, window: null };
  }

  return {
    elapsedMs: elapsed,
    remainingMs: Math.max(0, limitMs - elapsed),
    limitMs,
    isExpired,
    progress: Math.min(1, elapsed / limitMs),
    window: null,
  };
}

/** Elapsed time of the current segment: banked pause time plus the running stretch. */
export function liveElapsedMs(params: {
  pausedElapsed: number;
  segmentStartedAt: number | null;
  running: boolean;
  now: number;
}) {
  const { pausedElapsed, segmentStartedAt, running, now } = params;
  if (!running || segmentStartedAt === null) return pausedElapsed;
  return pausedElapsed + Math.max(0, now - segmentStartedAt);
}

export type CatchUpPlan = {
  /** Segments that ended on their own, with the exact time each one ran. */
  completed: { index: number; elapsedMs: number }[];
  /** Segment the athlete is in now. */
  index: number;
  /** Scheduled start of that segment (may be in the past). */
  segmentStartedAt: number;
};

/**
 * Advances through every segment that has already run out, starting each next
 * segment exactly when the previous one ended rather than "when the app
 * noticed". This keeps the app in step with a wall clock and fast-forwards
 * correctly after the screen was locked or the tab was in the background.
 *
 * `currentStartedAt` is the virtual start of the current segment
 * (`now - liveElapsedMs`). The plan stops at the first segment that is still
 * running or that `canAutoAdvance` rejects (e.g. it needs a score, or it is the
 * last segment) — the caller handles that segment's expiry itself.
 */
export function planCatchUp(
  segments: TimerSegment[],
  index: number,
  currentStartedAt: number,
  now: number,
  canAutoAdvance: (index: number) => boolean,
): CatchUpPlan {
  const completed: CatchUpPlan["completed"] = [];
  let current = index;
  let startedAt = currentStartedAt;

  while (current < segments.length - 1 && canAutoAdvance(current)) {
    const limit = segmentLimitMs(segments[current]!);
    if (limit === null || now - startedAt < limit) break;

    completed.push({ index: current, elapsedMs: limit });
    startedAt += limit;
    current += 1;
  }

  return { completed, index: current, segmentStartedAt: startedAt };
}
