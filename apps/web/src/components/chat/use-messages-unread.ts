"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchUnreadCount } from "@/api/messaging";
import { useConversationUnread } from "@/components/conversations/use-conversations";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

export const gymUnreadKey = (slug: string | null) => ["messages", "unread", slug] as const;

/**
 * The selected gym's unread threads. Kept current by the `notifications:changed`
 * event (TopNav) and by reading a thread, so it is fetched once, not polled.
 */
export function useGymUnreadCount(enabled: boolean) {
  const { tokens } = useSession();
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: gymUnreadKey(slug),
    enabled: enabled && Boolean(tokens?.access_token) && Boolean(slug),
    queryFn: () => fetchUnreadCount(tokens!.access_token, slug),
    staleTime: FRESHNESS.pushed,
  });
}

/**
 * ADR-196: one inbox, one count: the gym's unread threads plus person
 * conversations and message requests (ADR-193). Shown on Μηνύματα in the
 * bottom bar. TopNav shows the same gym count, from the same cache entry.
 */
export function useMessagesUnread() {
  const { status, tokens, currentUser } = useSession();
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser);
  const unreadQuery = useGymUnreadCount(authenticated);
  const conversations = useConversationUnread();
  if (!authenticated) return 0;
  return (unreadQuery.data?.unread_count ?? 0) + conversations.inbox + conversations.requests;
}
