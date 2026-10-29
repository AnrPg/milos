"use client";

import { useEffect } from "react";
import { useInfiniteQuery, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  CLUBS_KEY,
  FEED_KEY,
  WOD_KEY,
  fetchFeed,
  fetchMyClubs,
  fetchWodToday,
  type CommunityClub,
  type FeedFilter,
} from "@/api/community";
import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";

/**
 * The member's clubs across every gym they belong to (ADR-138). `enabled`
 * false reads only what is already cached (shell parts that need the clubs
 * only now and then).
 */
export function useMyClubs(enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: CLUBS_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchMyClubs(token!),
    staleTime: 60_000,
  });
}

/** The #wod card of one gym's club for today in the member's time zone. */
export function useWodToday(slug: string | null) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC";
  return useQuery({
    queryKey: [...WOD_KEY, slug, timezone],
    enabled: Boolean(token && slug),
    queryFn: () => fetchWodToday(token!, slug!, timezone),
    staleTime: 60_000,
  });
}

export function feedKey(filter: FeedFilter) {
  return [
    ...FEED_KEY,
    filter.clubId ?? null,
    filter.channelId ?? null,
    Boolean(filter.mine),
    [...(filter.types ?? [])].sort().join(","),
    Boolean(filter.coachesOnly),
  ] as const;
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

/**
 * Refetches open feeds when a club's posts change, and the clubs and groups
 * when its channels do (a group proposed, approved, joined or archived), on
 * topic `community:club:<id>`.
 */
export function useClubRealtime(clubs: CommunityClub[] | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const ids = (clubs ?? []).map((club) => club.id).join(",");

  useEffect(() => {
    if (!token || !ids) return;
    const refresh = () => {
      void queryClient.invalidateQueries({ queryKey: FEED_KEY });
      void queryClient.invalidateQueries({ queryKey: WOD_KEY });
    };
    const channelsChanged = () => {
      void queryClient.invalidateQueries({ queryKey: CLUBS_KEY });
      void queryClient.invalidateQueries({ queryKey: ["community", "groups"] });
      void queryClient.invalidateQueries({ queryKey: ["community", "group"] });
    };
    const unsubscribers = ids
      .split(",")
      .map((id) =>
        subscribeToTopic(token, `community:club:${id}`, {
          post_created: refresh,
          post_updated: refresh,
          post_deleted: refresh,
          channels_changed: channelsChanged,
        }),
      );
    return () => unsubscribers.forEach((leave) => leave());
  }, [token, ids, queryClient]);
}
