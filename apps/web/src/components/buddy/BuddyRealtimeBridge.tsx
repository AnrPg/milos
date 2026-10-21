"use client";

import { useEffect, useEffectEvent } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";

import { BUDDY_EVENT, BUDDY_RESYNC, applyBuddyEvent, applyCacheRefreshes, buddyTopic } from "./buddy-realtime";

/**
 * One subscription per session to the person's own `user:<id>` topic
 * (ADR-160): each `buddy:changed` refreshes the Buddy caches it concerns.
 * After a reconnect everything Buddy is refreshed once, in case an event
 * was missed while offline.
 */
export function BuddyRealtimeBridge() {
  const { currentUser, tokens } = useSession();
  const queryClient = useQueryClient();

  const handleEvent = useEffectEvent((payload: unknown) => {
    applyBuddyEvent(queryClient, payload);
  });
  const handleRejoin = useEffectEvent(() => applyCacheRefreshes(queryClient, BUDDY_RESYNC));

  useEffect(() => {
    if (!tokens?.access_token || !currentUser?.id) return;
    let joins = 0;
    return subscribeToTopic(
      tokens.access_token,
      buddyTopic(currentUser.id),
      { [BUDDY_EVENT]: handleEvent },
      {
        onJoin: () => {
          joins += 1;
          if (joins > 1) handleRejoin();
        },
      },
    );
  }, [currentUser?.id, tokens?.access_token]);

  return null;
}
