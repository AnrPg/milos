"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { startExecution } from "@/api/executions";
import { useSession } from "@/components/session-provider";

export type RepeatableEntry = {
  id: string;
  master_workout_id: string;
  scale_level_slug?: string | null;
};

/**
 * "Do it again" (ADR-098): start a new execution with source `repeat` that
 * references the client's earlier execution, then open the workout player.
 * The execute page loads the timer sequence (or switches to the free-text
 * player) from the new execution, like resuming any other execution.
 */
export function useRepeatWorkout() {
  const router = useRouter();
  const { tokens } = useSession();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null);

  async function repeat(entry: RepeatableEntry) {
    if (!tokens?.access_token || pendingId) return;
    setPendingId(entry.id);
    setError(null);
    try {
      const execution = await startExecution(tokens.access_token, {
        master_workout_id: entry.master_workout_id,
        scale_level_slug: entry.scale_level_slug ?? null,
        source: "repeat",
        source_reference_id: entry.id,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      });
      router.push(`/workouts/${execution.id}/execute`);
    } catch (requestError) {
      setError(requestError);
      setPendingId(null);
    }
  }

  return { repeat, pendingId, error, clearError: () => setError(null) };
}
