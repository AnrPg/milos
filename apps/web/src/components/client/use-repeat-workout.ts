"use client";

import { useWorkoutLauncher } from "@/components/client/use-workout-launcher";

export type RepeatableEntry = {
  id: string;
  master_workout_id: string;
  scale_level_slug?: string | null;
};

/**
 * "Do it again" (ADR-098): start a new execution with source `repeat` that
 * references the client's earlier execution, then open the workout player.
 */
export function useRepeatWorkout() {
  const { launch, pendingKey, error, clearError } = useWorkoutLauncher();

  function repeat(entry: RepeatableEntry) {
    return launch({
      key: entry.id,
      masterWorkoutId: entry.master_workout_id,
      scaleLevelSlug: entry.scale_level_slug ?? null,
      source: "repeat",
      sourceReferenceId: entry.id,
    });
  }

  return { repeat, pendingId: pendingKey, error, clearError };
}
