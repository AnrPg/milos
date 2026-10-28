"use client";

import { useRouter } from "next/navigation";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  CONVERSATIONS_KEY,
  CONVERSATIONS_UNREAD_KEY,
  acceptConversation,
  conversationKey,
  conversationListKey,
  declineConversation,
  fetchConversationUnreadCount,
  fetchConversations,
  openConversation,
  type ConversationFolder,
} from "@/api/conversations";
import { useSession } from "@/components/session-provider";
import { FRESHNESS } from "@/lib/query-policy";
import { useRealtimeFallbackInterval } from "@/lib/realtime";

import { CONVERSATIONS_FALLBACK_REFETCH_MS } from "./conversations-realtime";

export function useConversationsToken() {
  const { status, tokens } = useSession();
  return status === "authenticated" ? (tokens?.access_token ?? null) : null;
}

export const conversationHref = (conversationId: string) => `/messages/${encodeURIComponent(conversationId)}`;
export const REQUESTS_HREF = "/messages?folder=requests";

/** The unread-count query itself (for its loading or error state). */
export function useConversationUnreadQuery() {
  const token = useConversationsToken();
  const fallback = useRealtimeFallbackInterval(CONVERSATIONS_FALLBACK_REFETCH_MS);
  return useQuery({
    queryKey: CONVERSATIONS_UNREAD_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchConversationUnreadCount(token!),
    staleTime: FRESHNESS.pushed,
    refetchInterval: fallback,
  });
}

/**
 * How many person conversations hold unread messages, in the inbox and in
 * requests (0 until known). Live: the realtime bridge refreshes it.
 */
export function useConversationUnread(): { inbox: number; requests: number } {
  const data = useConversationUnreadQuery().data;
  return { inbox: data?.inbox ?? 0, requests: data?.requests ?? 0 };
}

/** A folder's conversations, latest first, page by page. */
export function useConversationList(folder: ConversationFolder, limit?: number) {
  const token = useConversationsToken();
  const fallback = useRealtimeFallbackInterval(CONVERSATIONS_FALLBACK_REFETCH_MS);
  return useInfiniteQuery({
    queryKey: [...conversationListKey(folder), limit ?? null],
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchConversations(token!, folder, pageParam, limit),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    refetchInterval: fallback,
  });
}

/** Opens (or finds) the conversation with a person and goes to it. */
export function useOpenConversation(onOpened?: () => void) {
  const token = useConversationsToken();
  const router = useRouter();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (personId: string) => openConversation(token!, personId),
    onSuccess: (conversation) => {
      queryClient.setQueryData(conversationKey(conversation.id), conversation);
      onOpened?.();
      router.push(conversationHref(conversation.id));
    },
  });
}

/** Accept or decline a message request; both refresh every list and count. */
export function useRequestActions() {
  const token = useConversationsToken();
  const queryClient = useQueryClient();
  const refresh = () => void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
  const accept = useMutation({
    mutationFn: (conversationId: string) => acceptConversation(token!, conversationId),
    onSuccess: (conversation) => {
      queryClient.setQueryData(conversationKey(conversation.id), conversation);
      refresh();
    },
  });
  const decline = useMutation({
    mutationFn: (conversationId: string) => declineConversation(token!, conversationId),
    onSuccess: (_done, conversationId) => {
      queryClient.removeQueries({ queryKey: conversationKey(conversationId) });
      refresh();
    },
  });
  return { accept, decline };
}
