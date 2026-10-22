import { FREE_TEXT_TIMER_METADATA_KEY, type FreeTextTimerPreset, parseFreeTextTimerPreset } from "@/lib/free-text-timer";
import { readTextSections, type TextSection, type TextSectionSource } from "@/lib/text-sections";

export type FreeTextExecutionWorkout = {
  id: string;
  title: string;
  type?: string | null;
  body: string;
  execution_id?: string | null;
  source?: "class_booking" | "assigned" | "self_selected" | string | null;
  source_reference_id?: string | null;
  /** Timer the coach attached to the workout, if any. */
  timer_preset?: FreeTextTimerPreset | null;
  /** ADR-180: the workout's text sections, each with its own timer ([] for plain free text). */
  sections?: TextSection[];
};

const STORAGE_KEY = "palee:free-text-execution";

export function storeFreeTextExecutionWorkout(workout: {
  id: string;
  title: string;
  type?: string | null;
  free_text_body?: string | null;
  workout_metadata?: Record<string, unknown> | null;
  authoring_mode?: string | null;
  sections?: TextSectionSource[] | null;
}, execution?: {
  id?: string | null;
  source?: string | null;
  source_reference_id?: string | null;
}) {
  if (typeof window === "undefined") return;

  const payload: FreeTextExecutionWorkout = {
    id: workout.id,
    title: workout.title,
    type: workout.type ?? null,
    body: workout.free_text_body ?? "",
    execution_id: execution?.id ?? null,
    source: execution?.source ?? null,
    source_reference_id: execution?.source_reference_id ?? null,
    timer_preset: parseFreeTextTimerPreset(workout.workout_metadata?.[FREE_TEXT_TIMER_METADATA_KEY]),
    sections: readTextSections(workout),
  };

  window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
}

export function clearFreeTextExecutionWorkout(workoutId?: string | null) {
  if (typeof window === "undefined") return;
  if (!workoutId) {
    window.sessionStorage.removeItem(STORAGE_KEY);
    return;
  }

  const current = readFreeTextExecutionWorkout(workoutId);
  if (current) window.sessionStorage.removeItem(STORAGE_KEY);
}

export function readFreeTextExecutionWorkout(workoutId?: string | null) {
  if (typeof window === "undefined") return null;

  const raw = window.sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as FreeTextExecutionWorkout;
    if (workoutId && parsed.id !== workoutId) return null;
    return parsed;
  } catch {
    return null;
  }
}
