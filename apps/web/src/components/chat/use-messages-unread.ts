"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchUnreadCount } from "@/api/messaging";
import { useConversationUnread } from "@/components/conversations/use-conversations";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";

/**
 * ADR-196: one inbox, one count: the gym's unread threads plus person
 * conversations and message requests (ADR-193). Shown on Μηνύματα in the
 * bottom bar. The gym count shares TopNav's query key, so its realtime
 * refresh updates it too.
 */
export function useMessagesUnread() {
  const { status, tokens, currentUser } = useSession();
  const slug = useOrganizationSlug();
  const authenticated = status === "authenticated" && Boolean(tokens?.access_token) && Boolean(currentUser);
  const unreadQuery = useQuery({
    queryKey: ["messages", "unread", slug],
    enabled: authenticated && Boolean(slug),
    queryFn: () => fetchUnreadCount(tokens!.access_token, slug),
    staleTime: 15 * 1000,
  });
  const conversations = useConversationUnread();
  if (!authenticated) return 0;
  return (unreadQuery.data?.unread_count ?? 0) + conversations.inbox + conversations.requests;
}
