import type { QueryClient } from "@tanstack/react-query";

import { PARTNERS_KEY, PARTNER_MATCHES_KEY, partnerMessagesKey } from "@/api/partners";

import type { CacheRefresh } from "@/components/buddy/buddy-realtime";
import { REALTIME_FALLBACK_REFETCH_MS } from "@/lib/query-policy";

/**
 * Live Partners updates (ADR-169 §7): one `partners:changed` event on the
 * person's own `user:<id>` topic, the one Buddy listens on, carrying the kind
 * and the match id only. This turns an event into the caches to refresh.
 */
export const PARTNERS_EVENT = "partners:changed";
/** The safety net behind the events, polled only while the live connection is down; a rejoin also resyncs. */
export const PARTNERS_FALLBACK_REFETCH_MS = REALTIME_FALLBACK_REFETCH_MS;

export type PartnersEventKind = "partner_match_changed" | "partner_message_created" | "partner_messages_read";
export type PartnersEvent = { kind: PartnersEventKind; match_id?: string };

const KINDS = new Set<string>(["partner_match_changed", "partner_message_created", "partner_messages_read"]);

export function parsePartnersEvent(payload: unknown): PartnersEvent | null {
  if (!payload || typeof payload !== "object") return null;
  const raw = payload as Record<string, unknown>;
  if (typeof raw.kind !== "string" || !KINDS.has(raw.kind)) return null;
  const matchId = typeof raw.match_id === "string" && raw.match_id ? raw.match_id : undefined;
  return { kind: raw.kind as PartnersEventKind, match_id: matchId };
}

const matches: CacheRefresh = { queryKey: PARTNER_MATCHES_KEY, exact: true };
const messages = (id?: string): CacheRefresh[] => (id ? [{ queryKey: partnerMessagesKey(id), exact: true }] : []);

export function partnersCacheRefreshes(event: PartnersEvent): CacheRefresh[] {
  switch (event.kind) {
    case "partner_message_created":
    case "partner_messages_read":
      return [matches, ...messages(event.match_id)];
    case "partner_match_changed":
      // A new match, an ended one, a block: the list, the conversation's state and the decks.
      return [{ queryKey: PARTNERS_KEY, exact: false }];
  }
}

export const PARTNERS_RESYNC: CacheRefresh[] = [{ queryKey: PARTNERS_KEY, exact: false }];

export function applyPartnersEvent(queryClient: Pick<QueryClient, "invalidateQueries">, payload: unknown): boolean {
  const event = parsePartnersEvent(payload);
  if (!event) return false;
  partnersCacheRefreshes(event).forEach(({ queryKey, exact }) => void queryClient.invalidateQueries({ queryKey, exact }));
  return true;
}
