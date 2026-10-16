import type { AssignedWorkoutPreview, AssignedWorkoutRecord } from "@/api/assigned-workouts";
import type { ExecutionSource } from "@/api/executions";
import type { ScheduleSlot, WorkoutPreview } from "@/api/schedule";
import type { SelectedTrainingSource } from "@/lib/training-log";

/**
 * One thing the member can train today, from any provider (brief §7.4, §7.10):
 * a booked class WOD or a coach programme. Box shows them as source chips on
 * the first card, always in the same order (class time, then programmes).
 */
export type TodayTrainingItem = {
  key: string;
  kind: "class" | "programme";
  /** Class start; programmes have none. */
  scheduledAt: string | null;
  /** The class name (classes) or the programme title (programmes). */
  sourceName: string;
  workout: WorkoutPreview | AssignedWorkoutPreview;
  /** How the execution is attributed when the member taps Έναρξη. */
  execution: { source: ExecutionSource; referenceId: string };
  /** Where injury warnings are evaluated and acknowledged. */
  injuryContext: { surface: "class_detail" | "assignment_detail"; id: string };
  /** The class this item belongs to, for the schedule deep link. */
  slotId: string | null;
  completed: boolean;
  /** The assignment's own Οδηγίες (ADR-140 §4), read before the workout's. */
  instructions?: string;
};

export type ActiveExecution = { id: string; status: string; master_workout_id?: string | null };

export type TodayTraining = {
  /** An unfinished execution always wins: Έναρξη resumes it instead of starting another. */
  resumeExecutionId: string | null;
  items: TodayTrainingItem[];
};

export function localIsoDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

const ACTIVE_BOOKING = new Set(["approved"]);

export function buildTodayTraining(input: {
  now: Date;
  scheduleSlots: ScheduleSlot[];
  assignments: AssignedWorkoutRecord[];
  executions: ActiveExecution[];
}): TodayTraining {
  const today = localIsoDate(input.now);
  const items: TodayTrainingItem[] = [];
  const variantIds = new Set<string>();

  const classes = input.scheduleSlots
    .filter((slot) => localIsoDate(new Date(slot.scheduled_at)) === today)
    .filter((slot) => ACTIVE_BOOKING.has(slot.current_user_booking?.status ?? ""))
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));

  for (const slot of classes) {
    // ADR-125: the member's own version of the class replaces the class WOD.
    const version = slot.my_version;
    if (version) {
      variantIds.add(version.assignment_id);
      items.push({
        key: `class:${slot.id}`,
        kind: "class",
        scheduledAt: slot.scheduled_at,
        sourceName: slot.name || slot.class_type?.name || version.workout.title,
        workout: version.workout,
        execution: { source: "assigned", referenceId: version.assignment_id },
        injuryContext: { surface: "assignment_detail", id: version.assignment_id },
        slotId: slot.id,
        completed: version.execution_status === "completed",
      });
      continue;
    }
    if (!slot.workout) continue;
    items.push({
      key: `class:${slot.id}`,
      kind: "class",
      scheduledAt: slot.scheduled_at,
      sourceName: slot.name || slot.class_type?.name || slot.workout.title,
      workout: slot.workout,
      execution: { source: "class_booking", referenceId: slot.current_user_booking!.id },
      injuryContext: { surface: "class_detail", id: slot.id },
      slotId: slot.id,
      completed: false,
    });
  }

  for (const assignment of input.assignments) {
    if (assignment.scheduled_for !== today) continue;
    if (assignment.my_athlete_status === "rejected") continue;
    if (variantIds.has(assignment.id)) continue;
    // A class version whose class is not booked today still belongs to that class.
    if (assignment.assignment_kind === "class_variant") continue;
    items.push({
      key: `programme:${assignment.id}`,
      kind: "programme",
      scheduledAt: null,
      sourceName: assignment.workout.title,
      workout: assignment.workout,
      execution: { source: "assigned", referenceId: assignment.id },
      injuryContext: { surface: "assignment_detail", id: assignment.id },
      slotId: null,
      completed: assignment.execution_status === "completed",
      instructions: assignment.instructions?.trim() || undefined,
    });
  }

  const active = input.executions.find((execution) => execution.status !== "completed");
  return { resumeExecutionId: active?.id ?? null, items };
}

/** The item a fresh visit selects: the first one not yet done, else the first. */
export function defaultTodayItem(items: TodayTrainingItem[]) {
  return items.find((item) => !item.completed) ?? items[0] ?? null;
}

type LogSources = {
  classes: Array<{ id: string; title: string; scoreable_sections: SelectedTrainingSource["scoreableSections"] }>;
  assignments: Array<{ id: string; title: string; scoreable_sections: SelectedTrainingSource["scoreableSections"] }>;
};

/**
 * The log source for Καταγραφή, when the item can be logged now. A class can
 * be logged once it has started (ADR-118); a programme from its day on.
 */
export function logSourceFor(item: TodayTrainingItem, sources: LogSources | undefined): SelectedTrainingSource | null {
  if (!sources) return null;
  if (item.kind === "class" && item.execution.source === "class_booking" && item.slotId) {
    const match = sources.classes.find((source) => source.id === item.slotId);
    return match
      ? { sourceType: "class", referenceId: match.id, title: match.title, scoreableSections: match.scoreable_sections }
      : null;
  }
  const match = sources.assignments.find((source) => source.id === item.execution.referenceId);
  return match
    ? { sourceType: "assigned_workout", referenceId: match.id, title: match.title, scoreableSections: match.scoreable_sections }
    : null;
}
