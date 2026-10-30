"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useState, useSyncExternalStore } from "react";

import type { ClassTimerPayload } from "@/api/class-timers";
import {
  fetchBoxScreenTimer,
  fetchBoxScreenToday,
  isScreenTokenRejected,
  renewBoxScreenToken,
  type BoxScreenPairing,
} from "@/api/box-screens";
import { nextChangeAt, storePairing, tokenNeedsRenewal } from "@/lib/box-screen";
import { subscribeScreenTopic } from "@/lib/box-screen-realtime";
import { classTimerPosition, clockOffsetMs } from "@/lib/class-timer";
import { FRESHNESS, REALTIME_FALLBACK_REFETCH_MS } from "@/lib/query-policy";

const TODAY_KEY = ["box-screen", "today"] as const;
const DAY_MS = 86_400_000;

const noSubscription = () => () => undefined;

/** False on the server and during hydration, true after: device-only reads wait for it. */
export function useHydrated() {
  return useSyncExternalStore(noSubscription, () => true, () => false);
}

/** This device's clock, ticking every `intervalMs` (paused with `intervalMs` null). */
export function useNow(intervalMs: number | null) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (intervalMs === null) return;
    const interval = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(interval);
  }, [intervalMs]);
  return now;
}

type TodayResult = { day: Awaited<ReturnType<typeof fetchBoxScreenToday>>; offsetMs: number };

/**
 * The paired TV's day (ADR-253): `/today`, read again on every refresh hint
 * and override on `box_screen:<box>`, at the moment the automatic focus can
 * change, and every two minutes while the socket is down. A rejected display
 * token (screen removed, or paired to another TV) unpairs the device.
 */
export function useBoxScreenToday(pairing: BoxScreenPairing, onUnpaired: () => void) {
  const queryClient = useQueryClient();
  const [credentials, setCredentials] = useState({ token: pairing.token, expiresAt: pairing.expires_at });
  const [connected, setConnected] = useState(false);
  const token = credentials.token;

  const today = useQuery<TodayResult>({
    queryKey: [...TODAY_KEY, pairing.screen.id],
    staleTime: FRESHNESS.pushed,
    refetchInterval: connected ? false : REALTIME_FALLBACK_REFETCH_MS,
    retry: (count, error) => !isScreenTokenRejected(error) && count < 2,
    queryFn: async () => {
      const sentAt = Date.now();
      const day = await fetchBoxScreenToday(token);
      return { day, offsetMs: clockOffsetMs(day.server_now, sentAt, Date.now()) };
    },
  });

  const refetch = today.refetch;
  const reload = useCallback(() => void refetch(), [refetch]);

  useEffect(() => {
    if (isScreenTokenRejected(today.error)) {
      queryClient.removeQueries({ queryKey: TODAY_KEY });
      onUnpaired();
    }
  }, [today.error, onUnpaired, queryClient]);

  // Renew the 90-day token once it has less than 60 days left (checked daily).
  useEffect(() => {
    let stopped = false;
    const check = async () => {
      if (!tokenNeedsRenewal(credentials.expiresAt, Date.now())) return;
      try {
        const renewed = await renewBoxScreenToken(credentials.token);
        if (stopped) return;
        storePairing({ ...pairing, token: renewed.token, expires_at: renewed.expires_at });
        setCredentials({ token: renewed.token, expiresAt: renewed.expires_at });
      } catch (error) {
        if (isScreenTokenRejected(error)) onUnpaired();
      }
    };
    const first = window.setTimeout(() => void check(), 0);
    const interval = window.setInterval(() => void check(), DAY_MS);
    return () => {
      stopped = true;
      window.clearTimeout(first);
      window.clearInterval(interval);
    };
  }, [credentials, onUnpaired, pairing]);

  // Refresh hints and this screen's overrides.
  useEffect(() => {
    let timeout: number | undefined;
    const soon = () => {
      window.clearTimeout(timeout);
      timeout = window.setTimeout(reload, 800);
    };
    const leave = subscribeScreenTopic(
      token,
      `box_screen:${pairing.box.id}`,
      { "box_screen:refresh": soon, "box_screen:override": reload },
      {
        onJoin: () => {
          setConnected(true);
          reload();
        },
        onDown: () => setConnected(false),
      },
    );
    return () => {
      window.clearTimeout(timeout);
      leave();
    };
  }, [pairing.box.id, reload, token]);

  // The clock on the wall, on the server's time.
  const offsetMs = today.data?.offsetMs ?? 0;
  const now = useNow(1000) + offsetMs;

  // Read /today again when a class starts or ends, its results window closes or a pin runs out.
  const changeAt = today.data ? nextChangeAt(today.data.day, now) : null;
  useEffect(() => {
    if (changeAt === null) return;
    const wait = Math.max(1000, changeAt - (Date.now() + offsetMs) + 1500);
    const timeout = window.setTimeout(reload, Math.min(wait, 2 ** 31 - 1));
    return () => window.clearTimeout(timeout);
  }, [changeAt, offsetMs, reload]);

  return { today: today.data?.day ?? null, error: today.error, token, now };
}

type TimerResult = { payload: ClassTimerPayload; offsetMs: number };

/** A class's timer on the TV: loaded, then followed on `class_timer:<slot>`. */
export function useBoxScreenTimer(token: string, slotId: string | null) {
  const queryClient = useQueryClient();
  const key = ["box-screen", "timer", slotId] as const;
  const timer = useQuery<TimerResult>({
    queryKey: key,
    enabled: Boolean(slotId),
    staleTime: FRESHNESS.pushed,
    retry: false,
    queryFn: async () => {
      const sentAt = Date.now();
      const payload = await fetchBoxScreenTimer(token, slotId!);
      return { payload, offsetMs: clockOffsetMs(payload.server_now, sentAt, Date.now()) };
    },
  });
  const refetch = timer.refetch;

  useEffect(() => {
    if (!slotId) return;
    const timerKey = ["box-screen", "timer", slotId] as const;
    return subscribeScreenTopic(
      token,
      `class_timer:${slotId}`,
      {
        "class_timer:updated": (pushed) =>
          queryClient.setQueryData<TimerResult>(timerKey, (current) => {
            const next = pushed as ClassTimerPayload;
            // Ignore pushes older than what is already shown.
            if (current && next.timer.lock_version < current.payload.timer.lock_version) return current;
            return { payload: next, offsetMs: current?.offsetMs ?? 0 };
          }),
      },
      { onJoin: () => void refetch() },
    );
  }, [queryClient, refetch, slotId, token]);

  const now = useNow(slotId ? 250 : null);
  const data = slotId ? timer.data ?? null : null;
  const position = data ? classTimerPosition(data.payload.segments, data.payload.timer, now + data.offsetMs) : null;
  return { payload: data?.payload ?? null, position };
}
