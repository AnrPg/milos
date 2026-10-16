"use client";

import { useEffect } from "react";
import { useInfiniteQuery, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  CLUBS_KEY,
  FEED_KEY,
  fetchFeed,
  fetchMyClubs,
  type CommunityClub,
  type FeedFilter,
} from "@/api/community";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";

/** The member's clubs across every gym they belong to (ADR-138). */
export function useMyClubs() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: CLUBS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchMyClubs(token!),
    staleTime: 60_000,
  });
}

export function feedKey(filter: FeedFilter) {
  return [...FEED_KEY, filter.clubId ?? null, filter.channelId ?? null, Boolean(filter.mine)] as const;
}

/** One feed (all clubs, one club, one channel or my posts), newest first. */
export function useFeed(filter: FeedFilter) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useInfiniteQuery({
    queryKey: feedKey(filter),
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchFeed(token!, filter, pageParam),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
  });
}

/** Refetches open feeds when a club's posts change (topic `community:club:<id>`). */
export function useClubRealtime(clubs: CommunityClub[] | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const ids = (clubs ?? []).map((club) => club.id).join(",");

  useEffect(() => {
    if (!token || !ids) return;
    const refresh = () => void queryClient.invalidateQueries({ queryKey: FEED_KEY });
    const unsubscribers = ids
      .split(",")
      .map((id) =>
        subscribeToTopic(token, `community:club:${id}`, {
          post_created: refresh,
          post_updated: refresh,
          post_deleted: refresh,
        }),
      );
    return () => unsubscribers.forEach((leave) => leave());
  }, [token, ids, queryClient]);
}
