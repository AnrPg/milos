"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  adminWorkoutGoalsKey,
  fetchAdminWorkoutGoals,
  fetchGoalFeedback,
  fetchWorkoutGoals,
  goalFeedbackKey,
  saveAdminWorkoutGoals,
  saveGoalFeedback,
  workoutGoalsKey,
  type GoalFeedbackEntryKind,
  type GoalFeedbackResponse,
  type SaveGoalFeedbackRequest,
  type SaveWorkoutGoalsRequest,
  type StaffWorkoutGoalsResponse,
} from "@/api/wod-goals";
import { useSession } from "@/components/session-provider";

export function useGoalsToken() {
  const { tokens } = useSession();
  return tokens?.access_token ?? null;
}

/** The coach's goals and the live suggestion; refetched by the editor after each draft autosave. */
export function useAdminWorkoutGoals(workoutId: string | null) {
  const token = useGoalsToken();
  return useQuery({
    queryKey: adminWorkoutGoalsKey(workoutId ?? ""),
    enabled: Boolean(token && workoutId),
    queryFn: () => fetchAdminWorkoutGoals(token!, workoutId!),
    refetchOnWindowFocus: false,
  });
}

export function useSaveAdminWorkoutGoals(workoutId: string | null) {
  const token = useGoalsToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: SaveWorkoutGoalsRequest) => saveAdminWorkoutGoals(token!, workoutId!, body),
    onSuccess: (data) => {
      if (!workoutId) return;
      queryClient.setQueryData<StaffWorkoutGoalsResponse>(adminWorkoutGoalsKey(workoutId), data);
      void queryClient.invalidateQueries({ queryKey: workoutGoalsKey(workoutId) });
    },
  });
}

/** A published workout's goals as members see them (null while hidden or missing). */
export function useWorkoutGoals(workoutId: string | null | undefined) {
  const token = useGoalsToken();
  return useQuery({
    queryKey: workoutGoalsKey(workoutId ?? ""),
    enabled: Boolean(token && workoutId),
    queryFn: () => fetchWorkoutGoals(token!, workoutId!),
    staleTime: 5 * 60_000,
    retry: false,
  });
}

export function useGoalFeedback(kind: GoalFeedbackEntryKind, entryId: string | null) {
  const token = useGoalsToken();
  return useQuery({
    queryKey: goalFeedbackKey(kind, entryId ?? ""),
    enabled: Boolean(token && entryId),
    queryFn: () => fetchGoalFeedback(token!, kind, entryId!),
    retry: false,
  });
}

export function useSaveGoalFeedback(kind: GoalFeedbackEntryKind, entryId: string | null) {
  const token = useGoalsToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: SaveGoalFeedbackRequest) => saveGoalFeedback(token!, kind, entryId!, body),
    onSuccess: (data) => {
      if (entryId) queryClient.setQueryData<GoalFeedbackResponse>(goalFeedbackKey(kind, entryId), data);
    },
  });
}
