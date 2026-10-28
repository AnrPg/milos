import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { WorkoutContentEntry } from "@/components/workouts/WorkoutContent";
import type { WorkoutDslVocabulary } from "@/lib/workout-dsl-suggestions";
import type { FreeTextTimerPreset } from "@/lib/free-text-timer";
import type { LoadMode, LoadProgression, PrescriptionUnit, WorkoutType } from "@/types/workout";

export type ScaleLevel = {
  id?: string;
  slug: string;
  label: string;
  sort_order: number;
  is_active: boolean;
};

export type ReplaceScaleLevelsRequest = {
  scale_levels: Array<{
    slug: string;
    label: string;
    sort_order: number;
  }>;
};

export type CreateWorkoutRequest = {
  title: string;
  type: WorkoutType;
  is_team_workout?: boolean;
  sections: Array<{
    name: string;
    order: number;
    scoreable?: boolean;
    score_config?: {
      type?: string;
      unit?: string;
      label?: string;
    } | null;
    timer_config?: Record<string, unknown> | null;
    exercises: Array<{
      name: string;
      description?: string | null;
      base_sets?: number | null;
      base_reps?: number | null;
      base_duration_seconds?: number | null;
      order: number;
      variations?: Array<{
        scale_level_slug: string;
        description?: string | null;
        sets?: number | null;
        reps?: number | null;
        duration_seconds?: number | null;
      }>;
    }>;
  }>;
};

export type WorkoutVariationRecord = {
  id?: string;
  description?: string | null;
  sets?: number | null;
  reps?: number | null;
  duration_seconds?: number | null;
  exercise_name_override?: string | null;
  prescription_value?: number | null;
  prescription_unit?: PrescriptionUnit | null;
  load_value?: number | null;
  load_mode?: LoadMode | null;
  set_prescriptions?: Array<{
    set_index: number;
    prescription_value?: number | null;
    prescription_unit?: PrescriptionUnit | null;
    load_value?: number | null;
    load_mode?: LoadMode | null;
    note?: string | null;
  }> | null;
  load_progression?: {
    mode: LoadProgression["mode"];
    direction: LoadProgression["direction"];
    start_value: number;
    start_mode: LoadMode;
    step_value: number;
    per_set_values: number[];
  } | null;
  excluded?: boolean;
  note?: string | null;
  scale_level: ScaleLevel;
};

export type WorkoutExerciseRecord = {
  id?: string;
  item_type?: "exercise" | "header";
  name: string;
  description?: string | null;
  sets?: number | null;
  prescription_value?: number | null;
  prescription_unit?: PrescriptionUnit | null;
  load_value?: number | null;
  load_mode?: LoadMode | null;
  set_prescriptions?: Array<{
    set_index: number;
    prescription_value?: number | null;
    prescription_unit?: PrescriptionUnit | null;
    load_value?: number | null;
    load_mode?: LoadMode | null;
    note?: string | null;
  }>;
  load_progression?: {
    mode: LoadProgression["mode"];
    direction: LoadProgression["direction"];
    start_value: number;
    start_mode: LoadMode;
    step_value: number;
    per_set_values: number[];
  } | null;
  superset_group_id?: string | null;
  alternating_group_id?: string | null;
  group_config?: { sets?: number | null; title?: string | null } | null;
  hr_zone?: number | null;
  tempo?: string | null;
  rest_seconds?: number | null;
  cluster_rest_seconds?: number | null;
  rest_pause_seconds?: number | null;
  pacing?: number | null;
  interval_assignment?: number | null;
  order: number;
  variations: WorkoutVariationRecord[];
  applied_variation?: WorkoutVariationRecord | null;
  note?: string | null;
};

export type WorkoutSectionRecord = {
  id?: string;
  parent_section_id?: string | null;
  name: string;
  order: number;
  scoreable: boolean;
  score_config?: {
    type?: string;
    unit?: string;
    label?: string;
  } | null;
  timer_config?: Record<string, unknown> | null;
  note?: string | null;
  section_metadata?: Record<string, unknown> | null;
  /** ADR-180: a text section of a workout written without the assistant. */
  free_text_body?: string | null;
  free_text_document?: Record<string, unknown> | null;
  /** ADR-180: the timer the coach picked for this text section. */
  timer_preset?: FreeTextTimerPreset | null;
  exercises: WorkoutExerciseRecord[];
};

/** ADR-223: one text section of a workout written without the assistant. */
export type TextSectionBody = {
  id: string | null;
  /** Null when the coach left the section untitled. */
  title: string | null;
  text: string;
  /** The editor's rich text (TipTap JSON). */
  document: Record<string, unknown> | null;
  timer: FreeTextTimerPreset | null;
  /** What the section is scored by; empty when it is not scored. */
  scoring: Array<Record<string, unknown>>;
};

/**
 * ADR-223: what a workout says, in the shape of how it was written. Full
 * responses carry `WorkoutBody`; lists carry `WorkoutBodySummary`.
 */
export type WorkoutBody =
  | {
      kind: "free_text";
      text: string | null;
      document: Record<string, unknown> | null;
      timer: Record<string, unknown> | null;
      /** The assistant also derived exercises (in `sections`). */
      structured: boolean;
    }
  | { kind: "text_sections"; sections: TextSectionBody[] }
  | {
      kind: "structured";
      sections: Array<{
        id: string | null;
        name: string;
        subtitle?: string | null;
        timer: Record<string, unknown> | null;
        scoreable: boolean;
        exercises: WorkoutExerciseRecord[];
      }>;
    };

export type WorkoutBodySummary =
  | { kind: "free_text"; excerpt: string | null; timer: Record<string, unknown> | null; structured: boolean }
  | { kind: "text_sections"; sections: Array<{ title: string | null; excerpt: string | null; timer: FreeTextTimerPreset | null; scored: boolean }> }
  | { kind: "structured"; sections: Array<{ name: string; timer: Record<string, unknown> | null; exercise_count: number }> };

/** How a workout was written; `sectioned_text` = text sections without the assistant (ADR-180). */
export type WorkoutAuthoringMode = "structured" | "quick_text" | "free_text" | "sectioned_text";

export type WorkoutRecord = {
  id: string;
  title: string;
  type: string;
  is_team_workout?: boolean;
  status?: string;
  created_by_id?: string;
  folder_id?: string | null;
  source_workout_id?: string | null;
  /** Emoji chosen by a coach or suggested by AI; null = keyword rules apply. */
  icon?: string | null;
  icon_source?: "ai" | "coach" | null;
  inserted_at?: string;
  updated_at?: string;
  scale_level?: ScaleLevel;
  available_scale_levels: ScaleLevel[];
  sections: WorkoutSectionRecord[];
  draft_data?: unknown;
  authoring_mode?: WorkoutAuthoringMode;
  dsl_version?: number | null;
  dsl_source?: string | null;
  dsl_document?: Record<string, unknown> | null;
  dsl_source_revision?: number;
  last_dsl_diagnostics?: WorkoutDslDiagnostic[];
  free_text_body?: string | null;
  free_text_document?: Record<string, unknown> | null;
  workout_metadata?: Record<string, unknown> | null;
  /** Οδηγίες and the rest of the workout's content; staff also get the coach-brief (ADR-140 §4). */
  content?: WorkoutContentEntry[];
  /** ADR-223: the full body in single-workout responses, a summary in lists. */
  body?: WorkoutBody | WorkoutBodySummary;
};

export type WorkoutFolder = {
  id: string;
  name: string;
  parent_id: string | null;
  created_by_id?: string | null;
  /** Set on folders the app maintains: athletes, athlete:<id>, classes, classes:<yyyy>[-mm[-dd]]. */
  system_key?: string | null;
};

export type MaterializedWorkoutResponse = {
  workout: WorkoutRecord;
  scales: WorkoutRecord[];
};

export type WorkoutDslDiagnostic = {
  code: string;
  severity: "error" | "warning";
  line: number;
  column: number;
  params: Record<string, unknown>;
};

export type WorkoutDslPreview = {
  version: number;
  workout: Record<string, unknown>;
  formatted_source: string;
  vocabulary: WorkoutDslVocabulary;
  diagnostics: WorkoutDslDiagnostic[];
};

export type WorkoutDslAuthoring = {
  version: number;
  source: string;
  document: Record<string, unknown> | null;
  source_revision: number;
  authoring_mode: "structured" | "quick_text";
  diagnostics: WorkoutDslDiagnostic[];
};

export type WorkoutDslManual = {
  version: number;
  markdown: string;
  templates: {
    workout: string;
    sections: Record<string, string>;
  };
  vocabulary: WorkoutDslVocabulary;
};

export type WorkoutDslPublishResult = {
  workout: WorkoutRecord;
  formatted_source: string;
  diagnostics: WorkoutDslDiagnostic[];
  execution_preview: {
    segment_count: number;
    timed_seconds: number;
    formats: string[];
  };
};

export async function listScaleLevels(token: string) {
  const response = await apiRequest<{ scale_levels: ScaleLevel[] }>("/admin/scale-levels", { token });
  return response.scale_levels;
}

export type FreeTextWorkoutAnalysis = components["schemas"]["FreeTextWorkoutAnalysis"];

/** ADR-180: what the workout editor may offer in this gym. */
export type WodAssistantAvailability = { wod_assistant_enabled: boolean };

export const WOD_ASSISTANT_AVAILABILITY_KEY = ["admin", "workouts", "authoring-settings"] as const;

export function fetchWorkoutAuthoringSettings(token: string) {
  return apiRequest<WodAssistantAvailability>("/admin/workouts/authoring-settings", { token });
}

export function analyzeFreeTextWorkout(token: string, text: string, locale: string) {
  return apiRequest<FreeTextWorkoutAnalysis>("/admin/workouts/free-text/analyze", {
    method: "POST",
    token,
    body: { text, locale },
  });
}

export async function parseWorkoutDsl(token: string, source: string) {
  return apiRequest<WorkoutDslPreview>("/admin/workouts/dsl/parse", {
    method: "POST",
    token,
    body: { source },
  });
}

export async function fetchWorkoutDslAuthoring(token: string, id: string) {
  return apiRequest<WorkoutDslAuthoring>(`/admin/workouts/${id}/dsl`, { token });
}

export async function fetchWorkoutDslManual(token: string) {
  return apiRequest<WorkoutDslManual>("/admin/workouts/dsl/manual", { token });
}

export async function publishWorkoutDsl(
  token: string,
  id: string,
  payload: {
    source: string;
    document: Record<string, unknown> | null;
    expected_source_revision: number;
    acknowledge_warnings: boolean;
  },
) {
  return apiRequest<WorkoutDslPublishResult>(`/admin/workouts/${id}/dsl/publish`, {
    method: "POST",
    token,
    body: payload,
  });
}

export async function replaceScaleLevels(token: string, payload: ReplaceScaleLevelsRequest) {
  const response = await apiRequest<{ scale_levels: ScaleLevel[] }>("/admin/scale-levels", {
    method: "PUT",
    token,
    body: payload,
  });

  return response.scale_levels;
}

export async function listAdminWorkouts(token: string) {
  const response = await apiRequest<{ workouts: WorkoutRecord[] }>("/admin/workouts", { token });
  return response.workouts;
}

export async function listWorkoutFolders(token: string) {
  const response = await apiRequest<{ folders: WorkoutFolder[] }>("/admin/workout-folders", { token });
  return response.folders;
}

export function createWorkoutFolder(token: string, body: { name: string; parent_id: string | null }) {
  return apiRequest<WorkoutFolder>("/admin/workout-folders", { token, method: "POST", body });
}

export function updateWorkoutFolder(token: string, id: string, body: { name: string; parent_id: string | null }) {
  return apiRequest<WorkoutFolder>(`/admin/workout-folders/${id}`, { token, method: "PATCH", body });
}

export function deleteWorkoutFolder(token: string, id: string) {
  return apiRequest<void>(`/admin/workout-folders/${id}`, { token, method: "DELETE" });
}

export function moveWorkoutToFolder(token: string, id: string, folderId: string | null) {
  return apiRequest<{ id: string; folder_id: string | null }>(`/admin/workouts/${id}/library`, {
    token,
    method: "PATCH",
    body: { folder_id: folderId },
  });
}

function stripNullDraftFields(payload: unknown) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return payload;
  }

  const record = { ...(payload as Record<string, unknown>) };

  if (record.type == null) {
    delete record.type;
  }

  if (record.title == null) {
    delete record.title;
  }

  return record;
}

function mapLegacyCreatePayload(payload: CreateWorkoutRequest) {
  return {
    title: payload.title,
    type: payload.type,
    sections: payload.sections.map((section) => ({
      name: section.name,
      scoreable: section.scoreable ?? false,
      score_config: section.score_config ?? null,
      timer_config: section.timer_config ?? { type: "untimed" },
      exercises: section.exercises.map((exercise) => ({
        name: exercise.name,
        sets: exercise.base_sets ?? 1,
        prescription_value: exercise.base_reps ?? exercise.base_duration_seconds ?? 1,
        prescription_unit: exercise.base_duration_seconds ? "secs" : "reps",
        variations: (exercise.variations ?? []).map((variation) => ({
          scale_level_slug: variation.scale_level_slug,
          exercise_name_override: variation.description ?? null,
          sets: variation.sets ?? null,
          prescription_value: variation.reps ?? variation.duration_seconds ?? null,
          prescription_unit: variation.duration_seconds ? "secs" : variation.reps ? "reps" : null,
        })),
      })),
    })),
  };
}

export async function createWorkout(token: string, payload: CreateWorkoutRequest) {
  const draft = await createDraftWorkout(token);
  const updatedDraft = await updateDraftWorkout(token, draft.id, {
    ...mapLegacyCreatePayload(payload),
    expected_source_revision: draft.dsl_source_revision ?? 0,
  });
  return publishWorkoutDraft(token, draft.id, {
    expected_source_revision: updatedDraft.dsl_source_revision ?? draft.dsl_source_revision ?? 0,
  });
}

export async function createDraftWorkout(
  token: string,
  folderId?: string | null,
): Promise<{
  id: string;
  status?: string;
  authoring_mode?: string;
  dsl_source_revision?: number;
}> {
  const response = await apiRequest<{
    draft: {
      id: string;
      status?: string;
      authoring_mode?: string;
      dsl_source_revision?: number;
    };
  }>("/admin/workouts", {
    method: "POST",
    token,
    ...(folderId ? { body: { folder_id: folderId } } : {}),
  });

  return response.draft;
}

export async function updateDraftWorkout(
  token: string,
  id: string,
  payload: unknown,
  options?: { editorSessionId?: string },
): Promise<{
  id: string;
  status?: string;
  authoring_mode?: string;
  dsl_source_revision?: number;
}> {
  const normalizedPayload = stripNullDraftFields(payload);
  const requestBody =
    options?.editorSessionId && normalizedPayload && typeof normalizedPayload === "object"
      ? {
          ...(normalizedPayload as Record<string, unknown>),
          editor_session_id: options.editorSessionId,
        }
      : normalizedPayload;

  const response = await apiRequest<{
    draft: {
      id: string;
      status?: string;
      authoring_mode?: string;
      dsl_source_revision?: number;
    };
  }>(
    `/admin/workouts/${id}/draft`,
    {
      method: "PATCH",
      token,
      body: requestBody,
    },
  );

  return response.draft;
}

export async function publishWorkout(token: string, id: string): Promise<WorkoutRecord> {
  const response = await apiRequest<{ workout: WorkoutRecord }>(`/admin/workouts/${id}/publish`, {
    method: "POST",
    token,
    body: {},
  });

  return response.workout;
}

export async function publishWorkoutDraft(
  token: string,
  id: string,
  payload: unknown,
): Promise<WorkoutRecord> {
  const response = await apiRequest<{ workout: WorkoutRecord }>(`/admin/workouts/${id}/publish`, {
    method: "POST",
    token,
    body: payload,
  });

  return response.workout;
}

export async function fetchAdminWorkout(token: string, id: string) {
  const response = await apiRequest<{ workout: WorkoutRecord }>(`/admin/workouts/${id}`, { token });
  return response.workout;
}

export async function deleteWorkout(token: string, id: string) {
  await apiRequest<void>(`/admin/workouts/${id}`, {
    method: "DELETE",
    token,
  });
}

export async function reopenWorkout(token: string, id: string): Promise<{ id: string; status: string }> {
  const response = await apiRequest<{ draft: { id: string; status: string } }>(
    `/admin/workouts/${id}/reopen`,
    { method: "POST", token, body: {} },
  );
  return response.draft;
}

export function setWorkoutIcon(token: string, id: string, icon: string | null) {
  return apiRequest<{ id: string; icon: string | null; icon_source: "ai" | "coach" | null }>(`/admin/workouts/${id}/icon`, {
    method: "PATCH",
    token,
    body: { icon },
  });
}

export async function copyWorkoutToFolder(token: string, id: string, folderId: string | null) {
  const response = await apiRequest<{ workout: WorkoutRecord }>(`/admin/workouts/${id}/copy`, {
    method: "POST",
    token,
    body: { folder_id: folderId },
  });
  return response.workout;
}

export async function duplicateWorkout(
  token: string,
  id: string,
  context?: { assignment_id?: string; slot_id?: string },
): Promise<{ id: string; status: string; title: string }> {
  const response = await apiRequest<{ draft: { id: string; status: string; title: string } }>(
    `/admin/workouts/${id}/duplicate`,
    { method: "POST", token, body: context ?? {} },
  );
  return response.draft;
}

export async function fetchWorkout(token: string, id: string) {
  const response = await apiRequest<{ workout: WorkoutRecord }>(`/workouts/${id}`, { token });
  return response.workout;
}

export async function fetchMaterializedWorkout(token: string, id: string) {
  return apiRequest<MaterializedWorkoutResponse>(`/workouts/${id}/scales`, { token });
}

export type TimerPreviewSegment = {
  label: string;
  label_key?: string | null;
  label_params?: Record<string, string | number> | null;
  kind: "countdown" | "countup" | "manual" | "no_timer" | "interval_cycle";
  phase: "work" | "rest" | "transition";
  duration_seconds: number | null;
  round: number | null;
  total_rounds: number | null;
};

export type TimerPreview = {
  segments: TimerPreviewSegment[];
  total_seconds: number;
  open_ended: boolean;
};

/** The exact timer sequence a draft section will run (same builder as execution). */
export async function previewSectionTimer(token: string, section: Record<string, unknown>) {
  return apiRequest<TimerPreview>("/admin/workouts/timer-preview", {
    method: "POST",
    token,
    body: { section },
  });
}
