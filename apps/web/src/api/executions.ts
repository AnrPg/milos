import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";
import type { JournalComment, JournalCommentChange } from "@/api/journal-comments";
import type { WorkoutRecord } from "@/api/workouts";
import type { WorkoutContentEntry } from "@/components/workouts/WorkoutContent";

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

/**
 * ADR-270: one set / round of a structured plan exercise, prescribed next to
 * actual, keyed by plan row id and its place in the run (block, round, part,
 * window). Sent on completion as `plan_actuals`.
 */
export type PlanSetActual = {
  section_id: string;
  row_id: string;
  exercise_name: string;
  exercise_ref: string | null;
  /** Block (kind of round) of the row; -1 for interrupt rows. */
  block_index: number;
  /** 1-based set / round / slot / interval number; for interrupt rows, which interruption. */
  round_index: number;
  /** 0-based part of a cluster / drop / rest-pause set; 0 otherwise. */
  part_index: number;
  /** 0-based phase (AMRAP window, EMOM slot…) the set was done in. */
  phase_index: number;
  interrupt: boolean;
  /** The prescription as shown ("8–12", "max", "400 m", "70%", "βαρύ"). */
  prescribed_reps_text: string;
  prescribed_load_text: string;
  /** Numeric prescription: plain reps / calories, load in kg (decimal; from % × 1RM when known). */
  prescribed_reps: number | null;
  prescribed_load_kg: number | null;
  /** A load prescribed as % of 1RM, and the 1RM (kg) used to compute `prescribed_load_kg`, when known. */
  prescribed_load_pct: number | null;
  one_rep_max_kg: number | null;
  actual_reps: number | null;
  actual_load_kg: number | null;
  /** The athlete typed a value for this set (otherwise actual = prescribed). */
  logged: boolean;
};

export async function completeExecution(
  token: string,
  executionId: string,
  params: {
    timezone?: string;
    checked_exercise_ids?: string[];
    section_scores?: SectionScore[];
    /** ADR-180: results for the scores a coach set on text sections. */
    text_section_scores?: { section_id: string; metric_key: string; value: number }[];
    total_elapsed_ms?: number;
    section_elapsed_ms?: Record<string, number>;
    segment_cycle_counts?: Record<string, number>;
    kpi_counters?: KpiCounters;
    duration_adjustments?: Record<string, number>;
    /** ADR-270: prescribed vs actual per set of a structured plan workout. */
    plan_actuals?: PlanSetActual[];
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

/** What the member reads before Έναρξη (ADR-140 §4): never a coach-brief. */
export type TimerBriefing = {
  assignment_instructions: string | null;
  workout: WorkoutContentEntry[];
  sections: Array<{ id: string; name: string; content: WorkoutContentEntry[] }>;
};

export type TimerSequence = { segments: TimerSegment[]; briefing: TimerBriefing | null };

export async function fetchTimerSequence(
  token: string,
  workoutId: string,
  params: {
    scaleSlug?: string | null;
    source: ExecutionSource;
    sourceReferenceId?: string | null;
  },
): Promise<TimerSequence> {
  const query = new URLSearchParams({ source: params.source });

  if (params.scaleSlug) query.set("scale", params.scaleSlug);
  if (params.sourceReferenceId) query.set("source_reference_id", params.sourceReferenceId);

  const path = `/workouts/${workoutId}/timer-sequence?${query.toString()}`;

  const data = await apiRequest<{ segments: TimerSegment[]; content?: TimerBriefing }>(path, { token });
  return { segments: data.segments, briefing: data.content ?? null };
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
