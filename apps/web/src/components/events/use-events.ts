"use client";

import { useMutation, useQuery, useQueryClient, type QueryClient, type QueryKey } from "@tanstack/react-query";

import { STAFF_EVENTS_KEY } from "@/api/admin-events";
import { FEED_KEY } from "@/api/community";
import {
  CLUBS_EVENTS_KEY,
  EVENTS_KEY,
  MY_EVENTS_KEY,
  clubEventsKey,
  fetchClubEvents,
  fetchClubsEvents,
  fetchMyEvents,
  rsvpEvent,
  type CommunityEvent,
  type EventListScope,
} from "@/api/events";
import { useSession } from "@/components/session-provider";

import { optimisticRsvp } from "./events";

/** Every cache that can hold an event: event pages and lists, the feeds and the box page's public posts. */
const EVENT_CACHES: QueryKey[] = [EVENTS_KEY, FEED_KEY, ["social", "box-posts"]];

type Patch = (event: CommunityEvent) => CommunityEvent;

/** Replaces one event wherever it sits in a cached value (lists, feed pages, a post's `event`). */
export function patchEventIn(value: unknown, eventId: string, patch: Patch): unknown {
  if (!value || typeof value !== "object") return value;
  if (Array.isArray(value)) {
    let changed = false;
    const next = value.map((entry) => {
      const patched = patchEventIn(entry, eventId, patch);
      if (patched !== entry) changed = true;
      return patched;
    });
    return changed ? next : value;
  }
  const record = value as Record<string, unknown>;
  if (record.id === eventId && typeof record.starts_at === "string" && typeof record.going_count === "number") {
    return patch(record as CommunityEvent);
  }
  let changed = false;
  const next: Record<string, unknown> = { ...record };
  for (const key of ["pages", "posts", "pinned", "event", "events"]) {
    if (!(key in record)) continue;
    const patched = patchEventIn(record[key], eventId, patch);
    if (patched !== record[key]) {
      next[key] = patched;
      changed = true;
    }
  }
  return changed ? next : value;
}

export function patchEventEverywhere(queryClient: QueryClient, eventId: string, patch: Patch) {
  for (const queryKey of EVENT_CACHES) {
    queryClient.setQueriesData({ queryKey }, (current: unknown) => patchEventIn(current, eventId, patch));
  }
}

/** After any change to an event: its page, every list, the feeds and staff's lists refetch. */
export function invalidateEvents(queryClient: QueryClient) {
  return Promise.all([
    queryClient.invalidateQueries({ queryKey: EVENTS_KEY }),
    queryClient.invalidateQueries({ queryKey: FEED_KEY }),
    queryClient.invalidateQueries({ queryKey: STAFF_EVENTS_KEY }),
  ]);
}

/**
 * «Θα έρθω» / «Δεν θα έρθω», answered at once on screen and rolled back if
 * the API refuses (a full event puts the person on the waitlist).
 */
export function useRsvp(eventId: string, inviteToken: string | null = null) {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (going: boolean) => rsvpEvent(tokens!.access_token, eventId, going, inviteToken),
    onMutate: async (going: boolean) => {
      await Promise.all(EVENT_CACHES.map((queryKey) => queryClient.cancelQueries({ queryKey })));
      const snapshot = EVENT_CACHES.flatMap((queryKey) => queryClient.getQueriesData({ queryKey }));
      patchEventEverywhere(queryClient, eventId, (event) => optimisticRsvp(event, going));
      return { snapshot };
    },
    onError: (_error, _going, context) => {
      for (const [queryKey, data] of context?.snapshot ?? []) queryClient.setQueryData(queryKey, data);
    },
    onSuccess: (fresh) => {
      // Lists keep their short preview of who's going; the rest is the API's answer.
      patchEventEverywhere(queryClient, eventId, (event) => ({ ...event, ...fresh, goers: fresh.goers ?? event.goers }));
    },
    onSettled: () => invalidateEvents(queryClient),
  });
}

export function useClubEvents(clubId: string, scope: EventListScope) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: clubEventsKey(clubId, scope),
    enabled: Boolean(token),
    queryFn: () => fetchClubEvents(token!, clubId, scope),
  });
}

/** The member's own upcoming events at any box (going or waiting). */
export function useMyEvents() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({ queryKey: MY_EVENTS_KEY, enabled: Boolean(token), queryFn: () => fetchMyEvents(token!), staleTime: 60_000 });
}

/** Upcoming events across every club the member can see. */
export function useClubsEvents() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({ queryKey: CLUBS_EVENTS_KEY, enabled: Boolean(token), queryFn: () => fetchClubsEvents(token!) });
}
