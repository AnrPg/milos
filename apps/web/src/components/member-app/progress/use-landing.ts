"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchLandingPayload } from "@/api/landing";
import { useSession } from "@/components/session-provider";

/**
 * The member's gamification read model (stats, badges, challenges,
 * leaderboard, quote). Αρχική and Πρόοδος both read it; realtime and
 * offline-sync bridges invalidate the same `["landing"]` key.
 */
export const LANDING_QUERY_KEY = ["landing"] as const;

export function useLanding() {
  const { tokens } = useSession();
  return useQuery({
    queryKey: LANDING_QUERY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchLandingPayload(tokens!.access_token),
  });
}
