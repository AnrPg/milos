import type { ClassTimerState } from "@/api/class-timers";
import type { TimerSegment } from "@/api/executions";
import { planCatchUp, readSegmentClock, segmentLimitMs, type SegmentClock } from "@/lib/timer-engine";

export type ClassTimerPosition = {
  status: ClassTimerState["status"];
  index: number;
  segment: TimerSegment | null;
  clock: SegmentClock | null;
  /** Milliseconds until the segment starts (get-ready / resume countdown); 0 once running. */
  startsInMs: number;
};

/**
 * Where a class timer is at `now`. Mirrors the server's
 * `ClassTimerMachine.catch_up/3`: segments that ran out are passed through on
 * schedule, and the last one running out finishes the timer — so the wall
 * display, the coach remote and members' phones all show the same clock
 * without any of them writing anything.
 */
export function classTimerPosition(
  segments: TimerSegment[],
  timer: ClassTimerState,
  now: number,
): ClassTimerPosition {
  const index = Math.min(timer.current_segment_index, Math.max(0, segments.length - 1));
  const segment = segments[index] ?? null;
  if (!segment) return { status: timer.status, index, segment: null, clock: null, startsInMs: 0 };

  const startedAt = timer.segment_started_at_utc ? Date.parse(timer.segment_started_at_utc) : null;

  if (timer.status !== "running" || startedAt === null) {
    return {
      status: timer.status,
      index,
      segment,
      clock: readSegmentClock(segment, timer.paused_elapsed_ms),
      startsInMs: 0,
    };
  }

  if (now < startedAt) {
    return {
      status: "running",
      index,
      segment,
      clock: readSegmentClock(segment, timer.paused_elapsed_ms),
      startsInMs: startedAt - now,
    };
  }

  const plan = planCatchUp(segments, index, startedAt - timer.paused_elapsed_ms, now, (i) => i < segments.length - 1);
  const current = segments[plan.index]!;
  const elapsed = now - plan.segmentStartedAt;
  const limit = segmentLimitMs(current);
  const finished = plan.index === segments.length - 1 && limit !== null && elapsed >= limit;

  return {
    status: finished ? "finished" : "running",
    index: plan.index,
    segment: current,
    clock: readSegmentClock(current, finished ? limit! : elapsed),
    startsInMs: 0,
  };
}

/**
 * Offset to add to this device's clock to match the server's, estimated from
 * a request's round trip (the server stamped `serverNow` roughly midway).
 */
export function clockOffsetMs(serverNow: string, sentAt: number, receivedAt: number) {
  const server = Date.parse(serverNow);
  if (Number.isNaN(server)) return 0;
  return server - (sentAt + receivedAt) / 2;
}
