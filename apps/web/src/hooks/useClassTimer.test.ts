import { act, renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";

import { useClassTimer } from "./useClassTimer";

const fetchClassTimer = vi.fn();
const sendClassTimerCommand = vi.fn();
const handlers: Record<string, (payload: unknown) => void> = {};

vi.mock("@/api/class-timers", () => ({
  fetchClassTimer: (...args: unknown[]) => fetchClassTimer(...args),
  sendClassTimerCommand: (...args: unknown[]) => sendClassTimerCommand(...args),
}));
vi.mock("@/lib/realtime", () => ({
  subscribeToTopic: (_token: string, _topic: string, events: Record<string, (payload: unknown) => void>) => {
    Object.assign(handlers, events);
    return () => undefined;
  },
}));

function payload(version: number, status = "ready") {
  return {
    class: { id: "slot-1", name: "WOD", scheduled_at: "2026-10-12T18:00:00Z", duration_minutes: 60 },
    workout: null,
    segments: [{ segment_key: "free-text:0", kind: "countdown", duration_seconds: 600, exercises: [], label: "" }],
    timer: {
      status,
      current_segment_index: 0,
      segment_started_at_utc: null,
      paused_elapsed_ms: 0,
      duration_adjustments: {},
      timer_preset: null,
      lock_version: version,
    },
    server_now: new Date().toISOString(),
  };
}

describe("useClassTimer", () => {
  beforeEach(() => {
    fetchClassTimer.mockReset();
    sendClassTimerCommand.mockReset();
  });

  it("sends commands with the current version and adopts the result", async () => {
    fetchClassTimer.mockResolvedValue(payload(1));
    sendClassTimerCommand.mockResolvedValue(payload(2, "running"));

    const { result } = renderHook(() => useClassTimer("token", "slot-1"));
    await waitFor(() => expect(result.current.payload).not.toBeNull());

    await act(async () => {
      await result.current.send({ command: "start" });
    });

    expect(sendClassTimerCommand).toHaveBeenCalledWith("token", "slot-1", { command: "start" }, 1);
    expect(result.current.payload?.timer.status).toBe("running");
  });

  it("refetches on a version conflict instead of re-sending", async () => {
    fetchClassTimer.mockResolvedValueOnce(payload(1)).mockResolvedValue(payload(5, "paused"));
    sendClassTimerCommand.mockRejectedValue(new ApiError(409, "stale", {} as never));

    const { result } = renderHook(() => useClassTimer("token", "slot-1"));
    await waitFor(() => expect(result.current.payload).not.toBeNull());

    await act(async () => {
      await result.current.send({ command: "next" });
    });

    expect(sendClassTimerCommand).toHaveBeenCalledTimes(1);
    expect(result.current.problem).toBe("conflict");
    expect(result.current.payload?.timer.lock_version).toBe(5);
  });

  it("applies live pushes but ignores stale ones", async () => {
    fetchClassTimer.mockResolvedValue(payload(3));
    const { result } = renderHook(() => useClassTimer("token", "slot-1"));
    await waitFor(() => expect(result.current.payload).not.toBeNull());

    act(() => handlers["class_timer:updated"]!(payload(4, "running")));
    expect(result.current.payload?.timer.lock_version).toBe(4);

    act(() => handlers["class_timer:updated"]!(payload(2, "ready")));
    expect(result.current.payload?.timer.lock_version).toBe(4);
  });
});
