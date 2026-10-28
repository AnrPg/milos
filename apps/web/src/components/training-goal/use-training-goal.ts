"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { TRAINING_GOAL_KEY, fetchTrainingGoal, updateTrainingGoal } from "@/api/gamification";
import { LANDING_QUERY_KEY } from "@/components/member-app/progress/use-landing";
import { useSession } from "@/components/session-provider";

/** My weekly goal (ADR-221): one shared query for settings and Πρόοδος. */
export function useTrainingGoal() {
  const { tokens } = useSession();
  return useQuery({
    queryKey: TRAINING_GOAL_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchTrainingGoal(tokens!.access_token),
  });
}

export function useSetTrainingGoal() {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (target: number) => updateTrainingGoal(tokens!.access_token, target),
    onSuccess: (goal) => {
      queryClient.setQueryData(TRAINING_GOAL_KEY, goal);
      void queryClient.invalidateQueries({ queryKey: LANDING_QUERY_KEY });
    },
  });
}
