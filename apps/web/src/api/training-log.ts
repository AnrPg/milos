import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type ListResponse =
  operations["MilosTrainingWeb.TrainingLogController.index"]["responses"][200]["content"]["application/json"];
type SourcesResponse =
  operations["MilosTrainingWeb.TrainingLogController.sources"]["responses"][200]["content"]["application/json"];
type EntryResponse =
  operations["MilosTrainingWeb.TrainingLogController.show"]["responses"][200]["content"]["application/json"];

export type TrainingLogEntry = ListResponse["entries"][number];
export type TrainingLogSources = SourcesResponse;
export type TrainingLogClassSource = SourcesResponse["classes"][number];
export type TrainingLogAssignmentSource = SourcesResponse["assignments"][number];
export type TrainingLogLibrarySource = SourcesResponse["library_workouts"][number];
export type TrainingLogScoreableSection = TrainingLogClassSource["scoreable_sections"][number];
export type TrainingLogSourceType = TrainingLogEntry["source_type"];
export type CreateTrainingLogRequest =
  operations["MilosTrainingWeb.TrainingLogController.create"]["requestBody"]["content"]["application/json"];
export type UpdateTrainingLogRequest =
  operations["MilosTrainingWeb.TrainingLogController.update"]["requestBody"]["content"]["application/json"];
export type PerformedExercise = NonNullable<CreateTrainingLogRequest["performed_exercises"]>[number];

const BASE = "/me/training-log";

export async function listTrainingLogEntries(token: string): Promise<TrainingLogEntry[]> {
  const data = await apiRequest<ListResponse>(`${BASE}/entries`, { token });
  return data.entries;
}

export async function fetchTrainingLogSources(token: string): Promise<TrainingLogSources> {
  return apiRequest<SourcesResponse>(`${BASE}/sources`, { token });
}

export async function createTrainingLogEntry(
  token: string,
  body: CreateTrainingLogRequest,
  options?: { organizationSlug?: string | null },
): Promise<TrainingLogEntry> {
  // ADR-102: an outbox replay pins the tenant the entry was logged in.
  const path = options?.organizationSlug
    ? `/org/${options.organizationSlug}${BASE}/entries`
    : `${BASE}/entries`;
  const data = await apiRequest<EntryResponse>(path, { method: "POST", token, body });
  return data.entry;
}

export async function updateTrainingLogEntry(
  token: string,
  entryId: string,
  body: UpdateTrainingLogRequest,
): Promise<TrainingLogEntry> {
  const data = await apiRequest<EntryResponse>(`${BASE}/entries/${entryId}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.entry;
}

export async function voidTrainingLogEntry(
  token: string,
  entryId: string,
  body: { reason?: string | null; expected_version?: number },
): Promise<TrainingLogEntry> {
  const data = await apiRequest<EntryResponse>(`${BASE}/entries/${entryId}/void`, {
    method: "POST",
    token,
    body,
  });
  return data.entry;
}
