"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchSocialSummary, SUMMARY_KEY } from "@/api/social";
import { useSession } from "@/components/session-provider";

/** The member's own counts: posts, followers, following and pending requests. */
export function useSocialSummary() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: SUMMARY_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchSocialSummary(token!),
  });
}
