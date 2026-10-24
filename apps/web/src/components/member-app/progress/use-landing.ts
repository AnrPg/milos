"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchLandingPayload, updateLeaderboardOptIn, type LandingPayload } from "@/api/landing";
import { useSession } from "@/components/session-provider";
import { useOrganizationMemberships } from "@/lib/membership-role";

/**
 * The member's gamification read model (stats, badges, challenges,
 * leaderboard, quote). Αρχική and Πρόοδος both read it; realtime and
 * offline-sync bridges invalidate the same `["landing"]` key.
 *
 * The payload is the gym's (`/org/:slug/landing`), so someone without any
 * membership has none: the query stays off and `noGym` is true, and callers
 * hide what depends on it instead of showing a «not found» error.
 */
export const LANDING_QUERY_KEY = ["landing"] as const;

export function useLanding() {
  const { tokens } = useSession();
  const memberships = useOrganizationMemberships();
  const hasGym = Array.isArray(memberships.data) && memberships.data.length > 0;
  const query = useQuery({
    queryKey: LANDING_QUERY_KEY,
    enabled: Boolean(tokens?.access_token) && hasGym,
    queryFn: () => fetchLandingPayload(tokens!.access_token),
  });
  return Object.assign(query, { noGym: memberships.isSuccess && !hasGym });
}

/** Join or leave the gym's opt-in leaderboard; the landing cache updates in place. */
export function useLeaderboardOptIn() {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (optedIn: boolean) => updateLeaderboardOptIn(tokens!.access_token, optedIn),
    onSuccess: (result) => {
      queryClient.setQueryData<LandingPayload>(LANDING_QUERY_KEY, (current) =>
        current
          ? {
              ...current,
              gamification: {
                ...current.gamification,
                leaderboard: {
                  ...current.gamification.leaderboard,
                  opted_in: result.opted_in,
                  visible: result.visible,
                  weekly: result.weekly,
                  monthly: result.monthly,
                },
              },
            }
          : current,
      );
    },
  });
}
