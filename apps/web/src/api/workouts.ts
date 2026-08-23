import { apiRequest } from "@/api/client";
import type { WorkoutDslVocabulary } from "@/lib/workout-dsl-suggestions";
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
  exercises: WorkoutExerciseRecord[];
};

export type WorkoutRecord = {
  id: string;
  title: string;
  type: string;
  is_team_workout?: boolean;
  status?: string;
  created_by_id?: string;
  folder_id?: string | null;
  source_workout_id?: string | null;
  inserted_at?: string;
  updated_at?: string;
  scale_level?: ScaleLevel;
  available_scale_levels: ScaleLevel[];
  sections: WorkoutSectionRecord[];
  draft_data?: unknown;
  authoring_mode?: "structured" | "quick_text" | "free_text";
  dsl_version?: number | null;
  dsl_source?: string | null;
  dsl_document?: Record<string, unknown> | null;
  dsl_source_revision?: number;
  last_dsl_diagnostics?: WorkoutDslDiagnostic[];
  free_text_body?: string | null;
  free_text_document?: Record<string, unknown> | null;
};

export type WorkoutFolder = {
  id: string;
  name: string;
  parent_id: string | null;
  created_by_id: string;
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
