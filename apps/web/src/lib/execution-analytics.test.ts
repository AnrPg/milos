import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import {
  createExecutionAnalytics,
  EXECUTION_INTERACTION_MAX_BATCH,
  EXECUTION_INTERACTION_MAX_QUEUE,
  type ExecutionInteractionEvent,
} from "@/lib/execution-analytics";

function setup(send = vi.fn().mockResolvedValue({ accepted: 1, duplicates: 0 })) {
  let counter = 0;
  const analytics = createExecutionAnalytics({
    executionId: "exec-1",
    getToken: () => "token-1",
    send,
    now: () => new Date("2026-10-12T10:00:00.000Z"),
    randomId: () => `00000000-0000-4000-8000-${String(++counter).padStart(12, "0")}`,
    flushIntervalMs: 0,
  });
  return { analytics, send };
}

describe("createExecutionAnalytics", () => {
  it("batches tracked interactions with client ids, timestamps and typed metadata", async () => {
    const { analytics, send } = setup();

    analytics.track("pause", { segment_index: 3, surface: "pause_sheet" });
    analytics.track("round_incremented", { round_count: 4 });
    analytics.track("ready_screen_shown");
    await analytics.flush();

    expect(send).toHaveBeenCalledTimes(1);
    const [token, executionId, events] = send.mock.calls[0] as [
      string,
      string,
      ExecutionInteractionEvent[],
    ];
    expect(token).toBe("token-1");
    expect(executionId).toBe("exec-1");
    expect(events).toEqual([
      {
        client_event_id: "00000000-0000-4000-8000-000000000001",
        kind: "pause",
        occurred_at: "2026-10-12T10:00:00.000Z",
        metadata: { segment_index: 3, surface: "pause_sheet" },
      },
      {
        client_event_id: "00000000-0000-4000-8000-000000000002",
        kind: "round_incremented",
        occurred_at: "2026-10-12T10:00:00.000Z",
        metadata: { round_count: 4 },
      },
      {
        client_event_id: "00000000-0000-4000-8000-000000000003",
        kind: "ready_screen_shown",
        occurred_at: "2026-10-12T10:00:00.000Z",
      },
    ]);
    expect(analytics.pending()).toBe(0);
  });

  it("splits large queues into server-sized batches", async () => {
    const { analytics, send } = setup();
    for (let i = 0; i < EXECUTION_INTERACTION_MAX_BATCH + 5; i += 1) analytics.track("resume");

    await analytics.flush();

    expect(send).toHaveBeenCalledTimes(2);
    expect((send.mock.calls[0][2] as unknown[]).length).toBe(EXECUTION_INTERACTION_MAX_BATCH);
    expect((send.mock.calls[1][2] as unknown[]).length).toBe(5);
  });

  it("keeps events for retry on transient failures and resends the same client ids", async () => {
    const send = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValue({ accepted: 1, duplicates: 0 });
    const { analytics } = setup(send);

    analytics.track("segment_skipped", { segment_index: 1, remaining_ms: 12_000 });
    await analytics.flush();
    expect(analytics.pending()).toBe(1);

    await analytics.flush();
    expect(analytics.pending()).toBe(0);
    expect(send.mock.calls[1][2]).toEqual(send.mock.calls[0][2]);
  });

  it("drops a batch the server rejects as outside the allowlist", async () => {
    const send = vi
      .fn()
      .mockRejectedValue(new ApiError(422, "invalid", { code: "invalid_execution_interactions" }));
    const { analytics } = setup(send);

    analytics.track("finish_wizard_opened");
    await expect(analytics.flush()).resolves.toBeUndefined();
    expect(analytics.pending()).toBe(0);
  });

  it("never throws, bounds the offline queue, and stops tracking after dispose", async () => {
    const send = vi.fn().mockRejectedValue(new ApiError(503, "down", {}));
    const { analytics } = setup(send);

    for (let i = 0; i < EXECUTION_INTERACTION_MAX_QUEUE + 10; i += 1) analytics.track("pause");
    expect(analytics.pending()).toBe(EXECUTION_INTERACTION_MAX_QUEUE);

    await expect(analytics.dispose()).resolves.toBeUndefined();
    analytics.track("resume");
    expect(analytics.pending()).toBe(EXECUTION_INTERACTION_MAX_QUEUE);
  });

  it("flushes periodically when an interval is configured", async () => {
    vi.useFakeTimers();
    try {
      const send = vi.fn().mockResolvedValue({ accepted: 1, duplicates: 0 });
      const analytics = createExecutionAnalytics({
        executionId: "exec-2",
        getToken: () => null,
        send,
        flushIntervalMs: 1_000,
      });

      analytics.track("cast_mode_toggled", { enabled: true, orientation: "landscape" });
      await vi.advanceTimersByTimeAsync(1_000);

      expect(send).toHaveBeenCalledTimes(1);
      await analytics.dispose();
    } finally {
      vi.useRealTimers();
    }
  });
});
