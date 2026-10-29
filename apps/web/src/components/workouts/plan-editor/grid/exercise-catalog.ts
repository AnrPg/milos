import type { WorkoutDslManual } from "@/api/workouts";

export type ExerciseSuggestion = { id: string; label: string; aliases: string[] };

/** The exercise library's names and aliases, from the workout DSL manual. */
export function catalogFromManual(manual: Pick<WorkoutDslManual, "vocabulary"> | null): ExerciseSuggestion[] {
  const catalog = (manual?.vocabulary as { exercise_catalog?: Array<{ id: string; label: string; aliases?: string[] }> } | undefined)
    ?.exercise_catalog;
  return (catalog ?? []).map((entry) => ({ id: entry.id, label: entry.label, aliases: entry.aliases ?? [] }));
}
