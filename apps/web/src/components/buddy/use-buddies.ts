"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  BUDDIES_KEY,
  SUPPORT_REQUESTS_KEY,
  fetchBuddies,
  fetchSupportRequest,
  fetchSupportRequests,
  sendSupportRequest,
  undoSupportRequest,
  type SupportRequest,
} from "@/api/buddies";
import { useSession } from "@/components/session-provider";

import { msUntilNudge } from "./buddy-model";
import { BUDDY_FALLBACK_REFETCH_MS } from "./buddy-realtime";

export function useBuddyToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/** My buddies, the people I support, invitations and settings. */
export function useBuddies(enabled = true) {
  const token = useBuddyToken();
  return useQuery({
    queryKey: BUDDIES_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchBuddies(token!),
    staleTime: 30_000,
    refetchInterval: BUDDY_FALLBACK_REFETCH_MS,
  });
}

/**
 * Requests I sent or received. Live updates (BuddyRealtimeBridge) refresh
 * them; the slow refetch is only a safety net.
 */
export function useSupportRequests(role: "sent" | "received", enabled = true) {
  const token = useBuddyToken();
  return useQuery({
    queryKey: [...SUPPORT_REQUESTS_KEY, role],
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchSupportRequests(token!, role),
    refetchInterval: BUDDY_FALLBACK_REFETCH_MS,
  });
}

/**
 * One request. Delivery, replies and the no-reply card arrive as live
 * updates; while it waits there is a slow safety-net refetch, and one more
 * when the undo window or the ten minutes run out, so the status card moves
 * on without a reload even if an event was missed.
 */
export function useSupportRequest(requestId: string | null, initial?: SupportRequest | null) {
  const token = useBuddyToken();
  const query = useQuery({
    queryKey: [...SUPPORT_REQUESTS_KEY, "one", requestId],
    enabled: Boolean(token && requestId),
    queryFn: () => fetchSupportRequest(token!, requestId!),
    initialData: initial ?? undefined,
    refetchInterval: (current) => {
      const data = current.state.data;
      if (!data || data.status === "undone" || (data.replies?.length ?? 0) > 0) return false;
      return BUDDY_FALLBACK_REFETCH_MS;
    },
  });
  const data = query.data;
  const refetch = query.refetch;
  useEffect(() => {
    if (!data) return;
    const timers: ReturnType<typeof setTimeout>[] = [];
    if (data.status === "sending" && data.undo_until) {
      const wait = Math.max(0, Date.parse(data.undo_until) - Date.now()) + 600;
      timers.push(setTimeout(() => void refetch(), wait));
    }
    const nudge = msUntilNudge(data, Date.now());
    if (nudge !== null && nudge > 0 && nudge < 11 * 60_000) timers.push(setTimeout(() => void refetch(), nudge + 500));
    return () => timers.forEach(clearTimeout);
  }, [data, refetch]);
  return query;
}

/** «Χρειάζομαι στήριξη»: send, then undo within five seconds. */
export function useSendSupport() {
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const send = useMutation({
    mutationFn: (message: string | null) => sendSupportRequest(token!, message),
    onSuccess: (request) => {
      queryClient.setQueryData([...SUPPORT_REQUESTS_KEY, "one", request.id], request);
      void queryClient.invalidateQueries({ queryKey: [...SUPPORT_REQUESTS_KEY, "sent"] });
    },
  });
  const undo = useMutation({
    mutationFn: (requestId: string) => undoSupportRequest(token!, requestId),
    onSuccess: (request) => {
      queryClient.setQueryData([...SUPPORT_REQUESTS_KEY, "one", request.id], request);
      void queryClient.invalidateQueries({ queryKey: [...SUPPORT_REQUESTS_KEY, "sent"] });
    },
  });
  return { send, undo };
}

/** A clock that ticks every `ms` while `active`. */
export function useNow(active: boolean, ms = 250) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(timer);
  }, [active, ms]);
  return now;
}
