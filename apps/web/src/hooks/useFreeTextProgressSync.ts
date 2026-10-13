"use client";

import { useCallback, useEffect, useRef } from "react";

import { ApiError } from "@/api/client";
import { type ExecutionProgressPayload, fetchExecution, updateExecutionProgress } from "@/api/executions";

/** How often a running free-text timer reports progress. */
export const FREE_TEXT_SAVE_INTERVAL_MS = 30_000;

export type FreeTextSnapshot = {
  running: boolean;
  /** Wall-clock start of the current running stretch. */
  startedAt: number | null;
  carriedMs: number;
  elapsedMs: number;
  kpi: ExecutionProgressPayload["kpi_counters"];
};

/**
 * Best-effort progress for free-text workouts. They have no structured
 * progress, but saving the clock and device counters while the athlete trains
 * lets the KPI report show where unfinished free-text workouts stopped, and
 * keeps pauses and start time even if the workout is never completed.
 *
 * Saves run one at a time; a version conflict refetches the version and
 * retries once. Failures are dropped: the next save carries everything again.
 */
export function useFreeTextProgressSync(
  accessToken: string | null | undefined,
  executionId: string | null | undefined,
  snapshot: () => FreeTextSnapshot,
) {
  const lockVersion = useRef<number | null>(null);
  const running = useRef<Promise<void> | null>(null);
  const again = useRef(false);
  const snapshotRef = useRef(snapshot);

  useEffect(() => {
    snapshotRef.current = snapshot;
  }, [snapshot]);

  const send = useCallback(async () => {
    if (!accessToken || !executionId) return;

    const attempt = async () => {
      if (lockVersion.current === null) {
        lockVersion.current = (await fetchExecution(accessToken, executionId)).lock_version;
      }
      const current = snapshotRef.current();
      const elapsed = Math.max(0, Math.round(current.elapsedMs));
      const payload: ExecutionProgressPayload = {
        expected_version: lockVersion.current,
        operation_id: crypto.randomUUID(),
        checked_exercise_ids: [],
        current_segment_index: 0,
        status: current.running ? "active" : "paused",
        segment_started_at_utc:
          current.running && current.startedAt !== null ? new Date(current.startedAt).toISOString() : null,
        paused_elapsed_ms: current.running ? Math.round(current.carriedMs) : elapsed,
        resume_countdown_ends_at_utc: null,
        total_elapsed_ms: elapsed,
        section_elapsed_ms: {},
        segment_cycle_counts: {},
        section_scores: [],
        kpi_counters: current.kpi,
      };
      const execution = await updateExecutionProgress(accessToken, executionId, payload);
      lockVersion.current = execution.lock_version;
    };

    try {
      await attempt();
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        lockVersion.current = null;
        try {
          await attempt();
        } catch {
          // Dropped; the next save retries with fresh state.
        }
      }
    }
  }, [accessToken, executionId]);

  /** Queues a save; saves requested while one runs collapse into one more. */
  const save = useCallback((): Promise<void> => {
    if (running.current) {
      again.current = true;
      return running.current;
    }
    const loop = async () => {
      do {
        again.current = false;
        await send();
      } while (again.current);
    };
    running.current = loop().finally(() => {
      running.current = null;
    });
    return running.current;
  }, [send]);

  // Periodic saves while the clock runs, and one when the page is hidden.
  useEffect(() => {
    const interval = window.setInterval(() => {
      if (snapshotRef.current().running) void save();
    }, FREE_TEXT_SAVE_INTERVAL_MS);
    const onHide = () => {
      if (document.visibilityState === "hidden") void save();
    };
    document.addEventListener("visibilitychange", onHide);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onHide);
    };
  }, [save]);

  return { save };
}
