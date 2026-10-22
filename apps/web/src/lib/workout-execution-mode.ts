type StructuredItem = { item_type?: unknown; [key: string]: unknown };
type StructuredSection = { exercises?: StructuredItem[] | null; sections?: StructuredSection[] | null; [key: string]: unknown };

export type ExecutableWorkout = {
  authoring_mode?: string | null;
  sections?: StructuredSection[] | null;
  workout_metadata?: Record<string, unknown> | null;
  [key: string]: unknown;
};

/** True when at least one section holds a real exercise (headers do not count). */
export function hasStructuredContent(sections: StructuredSection[] | null | undefined): boolean {
  return (sections ?? []).some(
    (section) =>
      (section.exercises ?? []).some((item) => (item.item_type ?? "exercise") === "exercise") ||
      hasStructuredContent(section.sections),
  );
}

/**
 * Free text is only an authoring convenience (ADR-109): every workout runs on
 * its structured timers. The manual timer is the fallback for free-text
 * workouts that have no runnable structure, or whose timers the assistant
 * could not infer (`workout_metadata.timer_inference = "incomplete"`), and
 * the only timer of workouts written in text sections (ADR-180).
 */
export function usesManualTimer(workout: ExecutableWorkout | null | undefined): boolean {
  // ADR-180: text sections never run a structured sequence, only their own timers.
  if (workout?.authoring_mode === "sectioned_text") return true;
  if (!workout || workout.authoring_mode !== "free_text") return false;
  if (!hasStructuredContent(workout.sections)) return true;
  return workout.workout_metadata?.timer_inference === "incomplete";
}
