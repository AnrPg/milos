"use client";

import { useEffect, useRef } from "react";

import type { ClassTimerPosition } from "@/lib/class-timer";
import { type CueMode, type CueSnapshot, nextCue, playCue } from "@/lib/timer-cues";

/** Beeps for the room: phase changes, the last 3 seconds, the get-ready count and the finish. */
export function useClassTimerCues(position: ClassTimerPosition | null, mode: CueMode) {
  const previous = useRef<CueSnapshot | null>(null);
  const previousStatus = useRef<ClassTimerPosition["status"] | null>(null);
  const previousGetReady = useRef<number | null>(null);

  const getReady = position && position.startsInMs > 0 ? Math.ceil(position.startsInMs / 1000) : null;
  const running = position?.status === "running" && getReady === null;
  const remaining =
    position?.clock?.remainingMs === null || position?.clock?.remainingMs === undefined
      ? null
      : Math.ceil(position.clock.remainingMs / 1000);
  const key = position?.segment ? `${position.index}#${position.clock?.window?.index ?? 0}` : null;
  const phase = position?.segment?.phase === "rest" || position?.segment?.phase === "transition" ? "rest" : "work";
  const status = position?.status ?? null;

  useEffect(() => {
    const snapshot: CueSnapshot = { segmentKey: key, running, remaining, phase };
    const cue = nextCue(previous.current, snapshot);
    previous.current = snapshot;
    if (cue) playCue(cue, mode);
  }, [key, mode, phase, remaining, running]);

  useEffect(() => {
    if (getReady !== null && getReady <= 3 && getReady !== previousGetReady.current) playCue("tick", mode);
    previousGetReady.current = getReady;
  }, [getReady, mode]);

  useEffect(() => {
    if (status === "finished" && previousStatus.current === "running") playCue("finish", mode);
    previousStatus.current = status;
  }, [mode, status]);
}
