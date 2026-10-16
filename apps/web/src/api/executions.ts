import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";
import type { JournalComment, JournalCommentChange } from "@/api/journal-comments";
import type { WorkoutRecord } from "@/api/workouts";

/** How an execution was started; `repeat` re-runs one of my earlier executions (ADR-098). */
export type ExecutionSource = "class_booking" | "assigned" | "self_selected" | "repeat";

export type TimerSegment = {
  segment_key: string;
  section_id: string;
  section_name: string;
  format: string;
  kind: "countdown" | "countup" | "manual" | "no_timer" | "interval_cycle";
  /** Work, rest inside a format, or a transition; older sequences omit it. */
  phase?: "work" | "rest" | "transition";
  /** Transition/rest inserted between sections; its time is not section time. */
  between_sections?: boolean;
  duration_seconds: number | null;
  round: number | null;
  total_rounds: number | null;
  label: string;
  /** Stable key for localizing `label`; absent when the label is the section name. */
  label_key?: string | null;
  label_params?: Record<string, string | number> | null;
  section_note?: string | null;
  scoreable: boolean;
  score_config: {
    type: string;
    unit?: string;
    label?: string;
  } | null;
  timer_config?: Record<string, unknown> | null;
  exercises: Array<{
    id: string;
    item_type?: "exercise" | "header";
    name: string;
    sets?: number | null;
    prescription_value?: number | null;
    prescription_unit?: string | null;
    load_value?: number | null;
    load_mode?: string | null;
    set_prescriptions?: Array<{
      set_index: number;
      prescription_value?: number | null;
      prescription_unit?: string | null;
      load_value?: number | null;
      load_mode?: string | null;
      note?: string | null;
    }>;
    load_progression?: Record<string, unknown> | null;
    superset_group_id?: string | null;
    alternating_group_id?: string | null;
    note?: string | null;
    interval_assignment?: number | null;
    /** Prescribed rest between this exercise's sets. */
    rest_seconds?: number | null;
    excluded?: boolean;
  }>;
};

export type WorkoutExecution = {
  id: string;
  user_id: string;
  master_workout_id: string | null;
  workout_title?: string | null;
  workout_type?: string | null;
  workout?: WorkoutRecord | null;
  scale_level_slug: string | null;
  source: string;
  source_reference_id: string | null;
  status: "active" | "paused" | "completed";
  started_at_utc: string;
  started_at_tz: string;
  completed_at_utc: string | null;
  completed_at_tz: string | null;
  current_segment_index: number;
  segment_started_at_utc: string | null;
  paused_elapsed_ms: number;
  resume_countdown_ends_at_utc: string | null;
  total_elapsed_ms: number;
  section_elapsed_ms: Record<string, number>;
  segment_cycle_counts: Record<string, number>;
  checked_exercise_ids: string[];
  section_scores: Array<{
    section_id: string;
    section_name?: string | null;
    value: number | string;
    unit?: string;
    score_type?: string;
    source?: string;
    kind?: string;
  }>;
  /** Σχόλια (ADR-140 §1); only reads of the execution carry them. */
  comments?: JournalComment[];
  lock_version: number;
  kpi_counters?: Record<string, number>;
  /** Mid-workout clock changes; older APIs omit the field. */
  duration_adjustments?: Record<string, DurationAdjustment | number>;
  inserted_at: string;
};

export type SectionScore = {
  section_id: string;
  section_name?: string | null;
  value: number | string;
  unit?: string;
  score_type?: string;
  source?: string;
  kind?: string;
};

/**
 * A change to the prescription, as recorded on a comment (ADR-140 §1): one
 * per row and field, keyed by `patch_id`. `note` is sent as the comment's
 * text.
 */
export type ExerciseModification = JournalCommentChange;

export type ExecutionProgressPayload = {
  expected_version: number;
  operation_id: string;
  checked_exercise_ids: string[];
  current_segment_index: number;
  status: "active" | "paused";
  segment_started_at_utc: string | null;
  paused_elapsed_ms: number;
  resume_countdown_ends_at_utc: string | null;
  total_elapsed_ms: number;
  section_elapsed_ms: Record<string, number>;
  segment_cycle_counts: Record<string, number>;
  section_scores: SectionScore[];
  kpi_counters?: KpiCounters;
  duration_adjustments?: Record<string, number>;
};

/** A stored mid-workout clock change, with the authored length for coaches. */
export type DurationAdjustment = {
  delta_seconds: number;
  authored_seconds: number;
  section_id?: string;
  section_name?: string | null;
  label?: string | null;
};

/** Device-observed execution KPIs; the API only ever lets them grow. */
export type KpiCounters = {
  skips?: number;
  countdown_skips?: number;
  countdown_segments?: number;
  pauses?: number;
  paused_ms?: number;
  finish_wizard_opens?: number;
  first_started_at_ms?: number;
};

export async function startExecution(
  token: string,
  params: {
    master_workout_id: string;
    scale_level_slug?: string | null;
    source: ExecutionSource;
    source_reference_id?: string | null;
    timezone?: string;
  },
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>("/executions", {
    method: "POST",
    token,
    body: params,
  });
  return data.execution;
}

export async function completeExecution(
  token: string,
  executionId: string,
  params: {
    timezone?: string;
    checked_exercise_ids?: string[];
    section_scores?: SectionScore[];
    total_elapsed_ms?: number;
    section_elapsed_ms?: Record<string, number>;
    segment_cycle_counts?: Record<string, number>;
    kpi_counters?: KpiCounters;
    duration_adjustments?: Record<string, number>;
  },
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>(
    `/executions/${executionId}/complete`,
    {
      method: "PATCH",
      token,
      body: params,
    },
  );
  return data.execution;
}

export async function updateExecutionProgress(
  token: string,
  executionId: string,
  params: ExecutionProgressPayload,
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>(
    `/executions/${executionId}/progress`,
    {
      method: "PATCH",
      token,
      body: params,
    },
  );

  return data.execution;
}

export async function fetchExecution(
  token: string,
  executionId: string,
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>(
    `/executions/${executionId}`,
    { token },
  );
  return data.execution;
}

export async function fetchTimerSequence(
  token: string,
  workoutId: string,
  params: {
    scaleSlug?: string | null;
    source: ExecutionSource;
    sourceReferenceId?: string | null;
  },
): Promise<TimerSegment[]> {
  const query = new URLSearchParams({ source: params.source });

  if (params.scaleSlug) query.set("scale", params.scaleSlug);
  if (params.sourceReferenceId) query.set("source_reference_id", params.sourceReferenceId);

  const path = `/workouts/${workoutId}/timer-sequence?${query.toString()}`;

  const data = await apiRequest<{ segments: TimerSegment[] }>(path, { token });
  return data.segments;
}

export async function listMyExecutions(token: string): Promise<WorkoutExecution[]> {
  const data = await apiRequest<{ executions: WorkoutExecution[] }>("/executions", {
    token,
  });
  return data.executions;
}

type VaultResponse =
  paths["/api/executions/vault"]["get"]["responses"][200]["content"]["application/json"];

export type VaultWorkout = VaultResponse["workouts"][number];
export type VaultEntry = VaultWorkout["entries"][number];

/** My completed workouts, each with its dated entries (ADR-098). Not tenant scoped. */
export async function fetchWorkoutVault(token: string): Promise<VaultWorkout[]> {
  const data = await apiRequest<VaultResponse>("/executions/vault", { token });
  return data.workouts;
}
