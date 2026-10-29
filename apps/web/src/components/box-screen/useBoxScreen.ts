"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";

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

/**
 * The paired TV's day (ADR-253): `/today`, read again on every refresh hint
 * and override on `box_screen:<box>`, at the moment the automatic focus can
 * change, and every two minutes while the socket is down. A rejected display
 * token (screen removed, or paired to another TV) unpairs the device.
 */
export function useBoxScreenToday(pairing: BoxScreenPairing, onUnpaired: () => void) {
  const queryClient = useQueryClient();
  const [token, setToken] = useState(pairing.token);
  const [expiresAt, setExpiresAt] = useState(pairing.expires_at);
  const [connected, setConnected] = useState(false);
  const [offsetMs, setOffsetMs] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const key = [...TODAY_KEY, pairing.screen.id] as const;

  const today = useQuery({
    queryKey: key,
    staleTime: FRESHNESS.pushed,
    refetchInterval: connected ? false : REALTIME_FALLBACK_REFETCH_MS,
    retry: (count, error) => !isScreenTokenRejected(error) && count < 2,
    queryFn: async () => {
      const sentAt = Date.now();
      const next = await fetchBoxScreenToday(token);
      setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
      return next;
    },
  });

  const refetch = today.refetch;
  const reload = useCallback(() => void refetch(), [refetch]);

  useEffect(() => {
    if (isScreenTokenRejected(today.error)) {
      storePairing(null);
      queryClient.removeQueries({ queryKey: TODAY_KEY });
      onUnpaired();
    }
  }, [today.error, onUnpaired, queryClient]);

  // Renew the 90-day token once it has less than 60 days left (checked daily).
  useEffect(() => {
    let stopped = false;
    const check = async () => {
      if (!tokenNeedsRenewal(expiresAt, Date.now())) return;
      try {
        const renewed = await renewBoxScreenToken(token);
        if (stopped) return;
        storePairing({ ...pairing, token: renewed.token, expires_at: renewed.expires_at });
        setExpiresAt(renewed.expires_at);
        setToken(renewed.token);
      } catch (error) {
        if (isScreenTokenRejected(error)) onUnpaired();
      }
    };
    void check();
    const interval = window.setInterval(() => void check(), DAY_MS);
    return () => {
      stopped = true;
      window.clearInterval(interval);
    };
  }, [expiresAt, onUnpaired, pairing, token]);

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
  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, []);

  // Read /today again when a class starts or ends, its results window closes or a pin runs out.
  const changeAt = today.data ? nextChangeAt(today.data, Date.now() + offsetMs) : null;
  useEffect(() => {
    if (changeAt === null) return;
    const wait = Math.max(1000, changeAt - (Date.now() + offsetMs) + 1500);
    const timeout = window.setTimeout(reload, Math.min(wait, 2 ** 31 - 1));
    return () => window.clearTimeout(timeout);
  }, [changeAt, offsetMs, reload]);

  return { today: today.data ?? null, error: today.error, token, now: now + offsetMs };
}

/** A class's timer on the TV: loaded, then followed on `class_timer:<slot>`. */
export function useBoxScreenTimer(token: string, slotId: string | null) {
  const [payload, setPayload] = useState<ClassTimerPayload | null>(null);
  const [offsetMs, setOffsetMs] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const latest = useRef<ClassTimerPayload | null>(null);

  const adopt = useCallback((next: ClassTimerPayload) => {
    if (latest.current && next.timer.lock_version < latest.current.timer.lock_version) return;
    latest.current = next;
    setPayload(next);
  }, []);

  const load = useCallback(async () => {
    if (!slotId) return;
    const sentAt = Date.now();
    try {
      const next = await fetchBoxScreenTimer(token, slotId);
      setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
      latest.current = null;
      adopt(next);
    } catch {
      // The class shows without a timer.
    }
  }, [adopt, slotId, token]);

  useEffect(() => {
    latest.current = null;
    setPayload(null);
    if (!slotId) return;
    return subscribeScreenTopic(
      token,
      `class_timer:${slotId}`,
      { "class_timer:updated": (next) => adopt(next as ClassTimerPayload) },
      { onJoin: () => void load() },
    );
  }, [adopt, load, slotId, token]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!slotId) return;
    const interval = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(interval);
  }, [slotId]);

  const position = payload ? classTimerPosition(payload.segments, payload.timer, now + offsetMs) : null;
  return { payload, position };
}
