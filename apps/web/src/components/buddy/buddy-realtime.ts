import type { QueryClient, QueryKey } from "@tanstack/react-query";

import { BUDDIES_KEY, SUPPORT_REQUESTS_KEY } from "@/api/buddies";
import { REALTIME_FALLBACK_REFETCH_MS } from "@/lib/query-policy";

/**
 * Live Buddy updates (ADR-160): the API sends one `buddy:changed` event on
 * the person's own `user:<id>` topic for each change that concerns them,
 * with ids only. This turns an event into the react-query caches to
 * refresh; nothing the event carries is shown as it is.
 */

export const BUDDY_TOPIC_PREFIX = "user:";
export const BUDDY_EVENT = "buddy:changed";
/** The safety net behind the events, polled only while the live connection is down; a rejoin also resyncs. */
export const BUDDY_FALLBACK_REFETCH_MS = REALTIME_FALLBACK_REFETCH_MS;

export type BuddyEventKind =
  | "support_request_sent"
  | "support_request_undone"
  | "support_request_delivered"
  | "support_request_nudged"
  | "support_reply_created"
  | "buddy_message_created"
  | "buddy_messages_read"
  | "buddy_link_changed";

export type BuddyEvent = { kind: BuddyEventKind; request_id?: string; link_id?: string };

export type CacheRefresh = { queryKey: QueryKey; exact: boolean };

const KINDS = new Set<string>([
  "support_request_sent",
  "support_request_undone",
  "support_request_delivered",
  "support_request_nudged",
  "support_reply_created",
  "buddy_message_created",
  "buddy_messages_read",
  "buddy_link_changed",
]);

const text = (value: unknown) => (typeof value === "string" && value.length > 0 ? value : undefined);

/** A channel payload as a known event, or null. */
export function parseBuddyEvent(payload: unknown): BuddyEvent | null {
  if (!payload || typeof payload !== "object") return null;
  const raw = payload as Record<string, unknown>;
  if (typeof raw.kind !== "string" || !KINDS.has(raw.kind)) return null;
  return { kind: raw.kind as BuddyEventKind, request_id: text(raw.request_id), link_id: text(raw.link_id) };
}

export const buddyTopic = (userId: string) => `${BUDDY_TOPIC_PREFIX}${userId}`;

const overview: CacheRefresh = { queryKey: BUDDIES_KEY, exact: true };
const sent: CacheRefresh = { queryKey: [...SUPPORT_REQUESTS_KEY, "sent"], exact: true };
const received: CacheRefresh = { queryKey: [...SUPPORT_REQUESTS_KEY, "received"], exact: true };
const request = (id?: string): CacheRefresh[] => (id ? [{ queryKey: [...SUPPORT_REQUESTS_KEY, "one", id], exact: true }] : []);
const messages = (id?: string): CacheRefresh[] => (id ? [{ queryKey: [...BUDDIES_KEY, id, "messages"], exact: true }] : []);

/** Which caches an event makes stale (the reducer from event to refreshes). */
export function buddyCacheRefreshes(event: BuddyEvent): CacheRefresh[] {
  switch (event.kind) {
    case "support_request_sent":
    case "support_request_undone":
    case "support_request_nudged":
      return [sent, ...request(event.request_id)];
    case "support_request_delivered":
      return [sent, received, ...request(event.request_id)];
    case "support_reply_created":
      return [sent, received, ...request(event.request_id), overview, ...messages(event.link_id)];
    case "buddy_message_created":
    case "buddy_messages_read":
      return [overview, ...messages(event.link_id)];
    case "buddy_link_changed":
      // Status, unread counts, candidates' link status and a conversation's read-only state.
      return [{ queryKey: BUDDIES_KEY, exact: false }];
  }
}

/** Everything Buddy, after a (re)join, since events may have been missed. */
export const BUDDY_RESYNC: CacheRefresh[] = [
  { queryKey: BUDDIES_KEY, exact: false },
  { queryKey: SUPPORT_REQUESTS_KEY, exact: false },
];

export function applyCacheRefreshes(queryClient: Pick<QueryClient, "invalidateQueries">, refreshes: CacheRefresh[]) {
  refreshes.forEach(({ queryKey, exact }) => void queryClient.invalidateQueries({ queryKey, exact }));
}

/** One channel payload: refresh what it concerns; unknown payloads change nothing. */
export function applyBuddyEvent(queryClient: Pick<QueryClient, "invalidateQueries">, payload: unknown): boolean {
  const event = parseBuddyEvent(payload);
  if (!event) return false;
  applyCacheRefreshes(queryClient, buddyCacheRefreshes(event));
  return true;
}
