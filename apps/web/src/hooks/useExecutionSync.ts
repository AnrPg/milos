"use client";

import { useCallback, useEffect, useRef } from "react";

import { fetchExecution, updateExecutionProgress } from "@/api/executions";
import { ApiError } from "@/api/client";
import { adoptLegacyCheckoffs } from "@/lib/legacy-offline-queue";
import { useExecutionStore } from "@/stores/execution";

export type SyncProblem = "offline" | "conflict" | "merged";

const RETRY_DELAY_MS = 5_000;

/**
 * Persists execution progress after it has already been applied locally.
 *
 * Progress is optimistic: the clock, navigation and check-offs update the
 * store immediately (timer-driven transitions cannot wait on the network
 * without drifting). This hook sends the latest full snapshot, one request at
 * a time: changes made while a request is in flight are coalesced into one
 * follow-up request carrying the new lock version. Failures keep the local
 * state, mark it pending and retry. On a version conflict another device
 * moved the workout on: its clock and position win, and this device's
 * check-offs, round counts and scores are replayed on top and resent.
 */
export function useExecutionSync(
  accessToken: string | null | undefined,
  executionId: string | null,
  onProblem: (problem: SyncProblem) => void,
) {
  const state = useRef({
    running: null as Promise<void> | null,
    again: false,
    retry: null as number | null,
    /** Latest `sync`, for retries scheduled by an earlier render's closure. */
    resync: (() => Promise.resolve()) as () => Promise<void>,
  });
  const onProblemRef = useRef(onProblem);

  useEffect(() => {
    onProblemRef.current = onProblem;
  }, [onProblem]);

  /** Sends local progress; resolves once everything queued so far is sent (or failed). */
  const sync = useCallback((): Promise<void> => {
    if (!accessToken || !executionId) return Promise.resolve();
    const current = state.current;

    if (current.retry !== null) {
      window.clearTimeout(current.retry);
      current.retry = null;
    }
    if (current.running) {
      current.again = true;
      return current.running;
    }

    useExecutionStore.getState().setPendingSync(true);

    const run = async () => {
      try {
        do {
          current.again = false;
          const store = useExecutionStore.getState();
          if (store.status === "completed" || store.executionId !== executionId) break;

          const payload = store.buildProgressPayload();
          if (!payload) break;

          const execution = await updateExecutionProgress(accessToken, executionId, payload);

          // A newer local change is waiting: keep local state, adopt the version.
          if (current.again) useExecutionStore.getState().acknowledge(execution);
          else useExecutionStore.getState().hydrateFromExecution(execution);
        } while (current.again);

        useExecutionStore.getState().setPendingSync(false);
      } catch (error) {
        if (useExecutionStore.getState().status === "completed") {
          useExecutionStore.getState().setPendingSync(false);
          return;
        }

        if (error instanceof ApiError && error.status === 409) {
          try {
            // Another device saved first: follow its timeline, but keep this
            // device's check-offs, rounds and scores by replaying them on top.
            const server = await fetchExecution(accessToken, executionId);
            const store = useExecutionStore.getState();
            if (store.rebaseOnto(server)) {
              current.again = true;
              onProblemRef.current("merged");
              return;
            }
            store.setPendingSync(false);
          } catch {
            // Leave pending; the retry below will try again.
          }
          onProblemRef.current("conflict");
        } else {
          onProblemRef.current("offline");
        }

        if (useExecutionStore.getState().pendingSync) {
          current.retry = window.setTimeout(() => {
            current.retry = null;
            void current.resync();
          }, RETRY_DELAY_MS);
        }
      }
    };

    current.running = run().finally(() => {
      current.running = null;
      // A change queued after the loop's last check still needs sending.
      if (current.again) {
        current.again = false;
        void current.resync();
      }
    });
    return current.running;
  }, [accessToken, executionId]);

  useEffect(() => {
    state.current.resync = sync;
  }, [sync]);

  useEffect(() => {
    const current = state.current;
    const flush = () => {
      if (useExecutionStore.getState().pendingSync) void current.resync();
    };

    // Local progress left unsynced by a previous visit (offline, tab closed),
    // including check-offs still in the retired IndexedDB queue.
    flush();
    if (executionId) void adoptLegacyCheckoffs(executionId).then((adopted) => adopted && flush());
    window.addEventListener("online", flush);
    return () => {
      window.removeEventListener("online", flush);
      if (current.retry !== null) window.clearTimeout(current.retry);
    };
  }, [executionId, sync]);

  /** True while local changes are unsent or a request is running. */
  const isSyncing = useCallback(
    () => state.current.running !== null || useExecutionStore.getState().pendingSync,
    [],
  );

  return { sync, isSyncing };
}
