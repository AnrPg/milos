import { apiRequest } from "@/api/client";

export type TimerSegment = {
  segment_key: string;
  section_id: string;
  section_name: string;
  format: string;
  kind: "countdown" | "countup" | "manual" | "no_timer" | "interval_cycle";
  duration_seconds: number | null;
  round: number | null;
  total_rounds: number | null;
  label: string;
  scoreable: boolean;
  score_config: {
    type: string;
    unit?: string;
    label?: string;
  } | null;
  timer_config?: Record<string, unknown> | null;
  exercises: Array<{
    id: string;
    name: string;
    sets?: number | null;
    prescription_value?: number | null;
    prescription_unit?: string | null;
    load_value?: number | null;
    load_mode?: string | null;
    interval_assignment?: number | null;
    excluded?: boolean;
  }>;
};

export type WorkoutExecution = {
  id: string;
  user_id: string;
  master_workout_id: string | null;
  workout_title?: string | null;
  workout_type?: string | null;
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
  exercise_notes: Array<{
    id: string;
    exercise_id: string;
    selected_text: string;
    selection_start?: number | null;
    selection_end?: number | null;
    tags?: string[];
    note_text?: string;
    inserted_at?: string;
    updated_at?: string;
  }>;
  exercise_modifications: ExerciseModification[];
  lock_version: number;
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

export type ExerciseModification = {
  exercise_id: string;
  type: "skipped" | "weight_changed" | "reps_changed" | "time_changed" | "other";
  prescribed_value?: number | null;
  actual_value?: number | null;
  prescribed_mins?: number | null;
  actual_mins?: number | null;
  sets?: number | null;
  note?: string | null;
  logged_at?: string;
};

export type ExerciseNote = {
  id?: string;
  exercise_id: string;
  selected_text: string;
  selection_start?: number | null;
  selection_end?: number | null;
  tags?: string[];
  note_text?: string;
};

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
};

export async function startExecution(
  token: string,
  params: {
    master_workout_id: string;
    scale_level_slug?: string | null;
    source: "class_booking" | "assigned" | "self_selected";
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
    exercise_notes?: ExerciseNote[];
    total_elapsed_ms?: number;
    section_elapsed_ms?: Record<string, number>;
    segment_cycle_counts?: Record<string, number>;
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

export async function submitExecutionNote(
  token: string,
  executionId: string,
  note: ExerciseNote,
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>(
    `/executions/${executionId}/notes`,
    {
      method: "POST",
      token,
      body: note,
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
    source: "class_booking" | "assigned" | "self_selected";
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

export async function addExecutionModifications(
  token: string,
  executionId: string,
  modifications: Omit<ExerciseModification, "logged_at">[],
): Promise<WorkoutExecution> {
  const data = await apiRequest<{ execution: WorkoutExecution }>(
    `/executions/${executionId}/modifications`,
    {
      method: "POST",
      token,
      body: { modifications },
    },
  );
  return data.execution;
}
