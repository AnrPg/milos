"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchWorkoutDslManual } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { catalogFromManual, type ExerciseSuggestion } from "./exercise-catalog";

const EMPTY: ExerciseSuggestion[] = [];

/**
 * The gym's exercise library for name suggestions: the same catalog the
 * text and structured editors read (`/admin/workouts/dsl/manual`,
 * vocabulary.exercise_catalog), fetched once per session.
 */
export function useExerciseCatalog(): ExerciseSuggestion[] {
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const query = useQuery({
    queryKey: ["admin", "workouts", "dsl-manual"],
    enabled: Boolean(token),
    queryFn: () => fetchWorkoutDslManual(token!),
    staleTime: Infinity,
    select: catalogFromManual,
  });
  return query.data ?? EMPTY;
}
