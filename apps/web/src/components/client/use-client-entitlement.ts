"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchMyEntitlement } from "@/api/my-finance";
import { useSession } from "@/components/session-provider";

export const CLIENT_ENTITLEMENT_QUERY_KEY = ["my", "entitlement"] as const;

/** The signed-in client's effective entitlement in the selected gym. */
export function useClientEntitlement(enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const query = useQuery({
    queryKey: CLIENT_ENTITLEMENT_QUERY_KEY,
    enabled: enabled && Boolean(token),
    queryFn: async () => (await fetchMyEntitlement(token!))?.entitlement ?? null,
    staleTime: 2 * 60 * 1000,
  });
  return {
    entitlement: query.data ?? null,
    isLoading: query.isPending && query.fetchStatus !== "idle",
    isError: query.isError,
  };
}
