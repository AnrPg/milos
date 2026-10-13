import { ApiError, apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

/**
 * Client-side execution analytics (ADR-123).
 *
 * Signals only the client can observe during a workout (pause sheet, manual
 * skip vs automatic advance, "+1 round", on-the-fly adjusts, ready screen and
 * get-ready countdown, finish wizard steps, cast mode) are queued here and
 * flushed in batches to `POST /api/executions/:id/interactions`.
 *
 * - Every event gets a client UUID, so retries are deduplicated server-side.
 * - Analytics never breaks the workout: `track` and `flush` never throw.
 * - Rejected batches (422: a kind/field outside the allowlist) are dropped,
 *   transient failures (network, 429, 5xx) are retried on the next flush.
 *
 * Usage (timer UI):
 *   const analytics = createExecutionAnalytics({ executionId, getToken });
 *   analytics.track("pause", { segment_index: 3, surface: "pause_sheet" });
 *   ...
 *   await analytics.dispose(); // on unmount / finish
 */

type InteractionBatch = NonNullable<
  paths["/api/executions/{id}/interactions"]["post"]["requestBody"]
>["content"]["application/json"];

export type ExecutionInteractionEvent = InteractionBatch["events"][number];
export type ExecutionInteractionKind = ExecutionInteractionEvent["kind"];
export type ExecutionInteractionMetadata = NonNullable<ExecutionInteractionEvent["metadata"]>;
export type ExecutionInteractionResult =
  paths["/api/executions/{id}/interactions"]["post"]["responses"]["202"]["content"]["application/json"];

/** Server-side batch limit (ExecutionInteraction.max_batch/0). */
export const EXECUTION_INTERACTION_MAX_BATCH = 50;
/** Events kept while offline; the oldest are dropped beyond this. */
export const EXECUTION_INTERACTION_MAX_QUEUE = 200;
export const EXECUTION_INTERACTION_FLUSH_INTERVAL_MS = 10_000;

export function sendExecutionInteractions(
  token: string | null | undefined,
  executionId: string,
  events: ExecutionInteractionEvent[],
) {
  return apiRequest<ExecutionInteractionResult>(`/executions/${executionId}/interactions`, {
    method: "POST",
    token: token ?? undefined,
    body: { events },
  });
}

type SendFn = typeof sendExecutionInteractions;

export type ExecutionAnalyticsOptions = {
  executionId: string;
  getToken: () => string | null | undefined;
  /** Injected for tests. */
  send?: SendFn;
  now?: () => Date;
  randomId?: () => string;
  /** 0 disables the periodic flush (flush manually or on dispose). */
  flushIntervalMs?: number;
};

export type ExecutionAnalytics = {
  track: (kind: ExecutionInteractionKind, metadata?: ExecutionInteractionMetadata) => void;
  flush: () => Promise<void>;
  dispose: () => Promise<void>;
  /** Number of events waiting to be sent. */
  pending: () => number;
};

function defaultRandomId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  // RFC 4122 v4 fallback for environments without crypto.randomUUID.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const random = (Math.random() * 16) | 0;
    return (char === "x" ? random : (random & 0x3) | 0x8).toString(16);
  });
}

function isPermanentRejection(error: unknown) {
  return error instanceof ApiError && (error.status === 422 || error.status === 404 || error.status === 403);
}

export function createExecutionAnalytics(options: ExecutionAnalyticsOptions): ExecutionAnalytics {
  const send = options.send ?? sendExecutionInteractions;
  const now = options.now ?? (() => new Date());
  const randomId = options.randomId ?? defaultRandomId;
  const flushIntervalMs = options.flushIntervalMs ?? EXECUTION_INTERACTION_FLUSH_INTERVAL_MS;

  let queue: ExecutionInteractionEvent[] = [];
  let inFlight: Promise<void> | null = null;
  let disposed = false;
  let timer: ReturnType<typeof setInterval> | null = null;

  if (flushIntervalMs > 0 && typeof setInterval === "function") {
    timer = setInterval(() => {
      void flush();
    }, flushIntervalMs);
  }

  function track(kind: ExecutionInteractionKind, metadata?: ExecutionInteractionMetadata) {
    if (disposed) return;
    try {
      queue.push({
        client_event_id: randomId(),
        kind,
        occurred_at: now().toISOString(),
        ...(metadata && Object.keys(metadata).length > 0 ? { metadata } : {}),
      });
      if (queue.length > EXECUTION_INTERACTION_MAX_QUEUE) {
        queue = queue.slice(queue.length - EXECUTION_INTERACTION_MAX_QUEUE);
      }
    } catch {
      // Analytics must never interrupt a workout.
    }
  }

  async function sendOnce() {
    while (queue.length > 0) {
      const batch = queue.slice(0, EXECUTION_INTERACTION_MAX_BATCH);
      try {
        await send(options.getToken(), options.executionId, batch);
      } catch (error) {
        if (!isPermanentRejection(error)) return; // keep for the next flush
      }
      const sent = new Set(batch.map((event) => event.client_event_id));
      queue = queue.filter((event) => !sent.has(event.client_event_id));
    }
  }

  function flush() {
    if (inFlight) return inFlight;
    if (queue.length === 0) return Promise.resolve();
    inFlight = sendOnce()
      .catch(() => undefined)
      .finally(() => {
        inFlight = null;
      });
    return inFlight;
  }

  async function dispose() {
    if (timer) clearInterval(timer);
    timer = null;
    await flush();
    disposed = true;
  }

  return { track, flush, dispose, pending: () => queue.length };
}
