import type { QueryClient } from "@tanstack/react-query";

import {
  CONVERSATIONS_KEY,
  CONVERSATIONS_UNREAD_KEY,
  CONVERSATION_LISTS_KEY,
  conversationKey,
  conversationMessagesKey,
} from "@/api/conversations";
import type { CacheRefresh } from "@/components/buddy/buddy-realtime";
import { REALTIME_FALLBACK_REFETCH_MS } from "@/lib/query-policy";

/**
 * Live person-conversation updates (ADR-193 §3): one `conversation:changed`
 * event on the person's own `user:<id>` topic, the one Buddy listens on,
 * carrying the kind and ids only, never a message's words. This turns an
 * event into the caches to refresh.
 */
export const CONVERSATION_EVENT = "conversation:changed";
/** The safety net behind the events, polled only while the live connection is down; a rejoin also resyncs. */
export const CONVERSATIONS_FALLBACK_REFETCH_MS = REALTIME_FALLBACK_REFETCH_MS;

export type ConversationEventKind = "message_created" | "read" | "folder_changed";
export type ConversationEvent = { kind: ConversationEventKind; conversation_id: string; message_id?: string };

const KINDS = new Set<string>(["message_created", "read", "folder_changed"]);

const text = (value: unknown) => (typeof value === "string" && value.length > 0 ? value : undefined);

/** A channel payload as a known event, or null. */
export function parseConversationEvent(payload: unknown): ConversationEvent | null {
  if (!payload || typeof payload !== "object") return null;
  const raw = payload as Record<string, unknown>;
  const conversationId = text(raw.conversation_id);
  if (typeof raw.kind !== "string" || !KINDS.has(raw.kind) || !conversationId) return null;
  return { kind: raw.kind as ConversationEventKind, conversation_id: conversationId, message_id: text(raw.message_id) };
}

const lists: CacheRefresh = { queryKey: CONVERSATION_LISTS_KEY, exact: false };
const unread: CacheRefresh = { queryKey: CONVERSATIONS_UNREAD_KEY, exact: true };

/** Which caches an event makes stale. */
export function conversationCacheRefreshes(event: ConversationEvent): CacheRefresh[] {
  const one: CacheRefresh = { queryKey: conversationKey(event.conversation_id), exact: true };
  switch (event.kind) {
    case "message_created":
      return [lists, unread, one, { queryKey: conversationMessagesKey(event.conversation_id), exact: true }];
    case "read":
    case "folder_changed":
      // Unread state, or the folder a conversation sits in (accepted elsewhere, a reply).
      return [lists, unread, one];
  }
}

/** Everything conversation, after a (re)join, since events may have been missed. */
export const CONVERSATIONS_RESYNC: CacheRefresh[] = [{ queryKey: CONVERSATIONS_KEY, exact: false }];

export function applyConversationEvent(queryClient: Pick<QueryClient, "invalidateQueries">, payload: unknown): boolean {
  const event = parseConversationEvent(payload);
  if (!event) return false;
  conversationCacheRefreshes(event).forEach(({ queryKey, exact }) => void queryClient.invalidateQueries({ queryKey, exact }));
  return true;
}
