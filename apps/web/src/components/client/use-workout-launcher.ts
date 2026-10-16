"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { startExecution, type ExecutionSource } from "@/api/executions";
import { useSession } from "@/components/session-provider";

export type WorkoutLaunch = {
  /** Identifies the launch for pending state (a card, an entry, an item). */
  key: string;
  masterWorkoutId: string;
  source: ExecutionSource;
  sourceReferenceId?: string | null;
  scaleLevelSlug?: string | null;
};

/**
 * Starts (or resumes) a workout in the unchanged execution screen. The
 * execute page loads the timer sequence, or switches to the free-text player,
 * from the execution itself, so every entry point (Box Έναρξη, Vault
 * Επανάληψη) launches the same way.
 */
export function useWorkoutLauncher() {
  const router = useRouter();
  const { tokens } = useSession();
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null);

  async function launch(request: WorkoutLaunch) {
    if (!tokens?.access_token || pendingKey) return;
    setPendingKey(request.key);
    setError(null);
    try {
      const execution = await startExecution(tokens.access_token, {
        master_workout_id: request.masterWorkoutId,
        scale_level_slug: request.scaleLevelSlug ?? null,
        source: request.source,
        source_reference_id: request.sourceReferenceId ?? null,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      });
      router.push(`/workouts/${execution.id}/execute`);
    } catch (requestError) {
      setError(requestError);
      setPendingKey(null);
    }
  }

  function resume(executionId: string) {
    router.push(`/workouts/${executionId}/execute`);
  }

  return { launch, resume, pendingKey, error, clearError: () => setError(null) };
}
