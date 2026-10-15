"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchWorkoutVault } from "@/api/executions";
import { useSession } from "@/components/session-provider";

export const WORKOUT_VAULT_QUERY_KEY = ["executions", "vault"] as const;

/** Every completed execution, grouped by workout (ADR-098). */
export function useWorkoutVault() {
  const { tokens } = useSession();
  return useQuery({
    queryKey: WORKOUT_VAULT_QUERY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutVault(tokens!.access_token),
  });
}
