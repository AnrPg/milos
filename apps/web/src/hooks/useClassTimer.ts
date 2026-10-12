"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  type ClassTimerCommand,
  type ClassTimerPayload,
  fetchClassTimer,
  sendClassTimerCommand,
} from "@/api/class-timers";
import { classTimerPosition, clockOffsetMs } from "@/lib/class-timer";
import { subscribeToTopic } from "@/lib/realtime";

const TICK_MS = 250;

export type ClassTimerProblem = "conflict" | "rejected" | "offline" | "forbidden" | null;

/**
 * Follows a class timer live: loads it, applies every update pushed on
 * `class_timer:<slot>`, refetches after reconnecting or returning to the tab,
 * and corrects for this device's clock being off from the server's.
 * `send` runs coach commands one at a time against the latest version; a
 * conflict refetches instead of re-sending, so "Next" is never applied twice.
 */
export function useClassTimer(accessToken: string | null | undefined, slotId: string | null) {
  const [payload, setPayload] = useState<ClassTimerPayload | null>(null);
  const [loadError, setLoadError] = useState<unknown>(null);
  const [connected, setConnected] = useState(false);
  const [problem, setProblem] = useState<ClassTimerProblem>(null);
  const [sending, setSending] = useState(false);
  const [offsetMs, setOffsetMs] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const latest = useRef<ClassTimerPayload | null>(null);
  const queue = useRef<Promise<unknown>>(Promise.resolve());

  const adopt = useCallback((next: ClassTimerPayload) => {
    // Ignore pushes older than what we already have.
    if (latest.current && next.timer.lock_version < latest.current.timer.lock_version) return;
    latest.current = next;
    setPayload(next);
  }, []);

  const refresh = useCallback(async () => {
    if (!accessToken || !slotId) return;
    const sentAt = Date.now();
    try {
      const next = await fetchClassTimer(accessToken, slotId);
      setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
      latest.current = null;
      adopt(next);
      setLoadError(null);
    } catch (error) {
      setLoadError(error);
    }
  }, [accessToken, adopt, slotId]);

  // Initial load (refresh() handles later reloads).
  useEffect(() => {
    if (!accessToken || !slotId) return;
    let cancelled = false;
    const sentAt = Date.now();
    fetchClassTimer(accessToken, slotId)
      .then((next) => {
        if (cancelled) return;
        setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
        latest.current = null;
        adopt(next);
      })
      .catch((error: unknown) => {
        if (!cancelled) setLoadError(error);
      });
    return () => {
      cancelled = true;
    };
  }, [accessToken, adopt, slotId]);

  useEffect(() => {
    if (!accessToken || !slotId) return;
    return subscribeToTopic(
      accessToken,
      `class_timer:${slotId}`,
      { "class_timer:updated": (next) => adopt(next as ClassTimerPayload) },
      {
        onJoin: () => {
          setConnected(true);
          void refresh();
        },
        onDisconnect: () => setConnected(false),
        onChannelError: () => setConnected(false),
        onJoinError: () => setConnected(false),
      },
    );
  }, [accessToken, adopt, refresh, slotId]);

  useEffect(() => {
    const tick = () => setNow(Date.now());
    const interval = window.setInterval(tick, TICK_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") {
        tick();
        void refresh();
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onVisible);
    };
  }, [refresh]);

  const send = useCallback(
    (command: ClassTimerCommand) => {
      if (!accessToken || !slotId) return Promise.resolve(false);
      const run = async () => {
        const current = latest.current;
        if (!current) return false;
        setSending(true);
        setProblem(null);
        const sentAt = Date.now();
        try {
          const next = await sendClassTimerCommand(accessToken, slotId, command, current.timer.lock_version);
          setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
          adopt(next);
          return true;
        } catch (error) {
          if (error instanceof ApiError && error.status === 409) {
            setProblem("conflict");
            await refresh();
          } else if (error instanceof ApiError && error.status === 403) {
            setProblem("forbidden");
          } else if (error instanceof ApiError && error.status === 422) {
            setProblem("rejected");
          } else {
            setProblem("offline");
          }
          return false;
        } finally {
          setSending(false);
        }
      };
      const result = queue.current.then(run, run);
      queue.current = result;
      return result;
    },
    [accessToken, adopt, refresh, slotId],
  );

  const serverNow = now + offsetMs;
  const position = payload ? classTimerPosition(payload.segments, payload.timer, serverNow) : null;

  return { payload, position, serverNow, connected, loadError, problem, sending, send, refresh };
}
