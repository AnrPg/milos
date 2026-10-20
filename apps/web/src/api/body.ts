import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { CommunityPost } from "@/api/community";
import type { MediaUpload } from "@/api/media";

/**
 * Ημερολόγιο › Σώμα (ADR-158): measurement snapshots with optional private
 * photos, a series per metric, comparing two snapshots, settings, the
 * body-photo consent, the log of coach reads, sharing a before/after, and
 * the coach's read of a client's shared snapshots. Weight and body fat leave
 * the server only as the person chose (`withheld_metrics`, `display`).
 */
export type BodySnapshot = components["schemas"]["BodySnapshot"];
export type BodySnapshotPage = components["schemas"]["BodySnapshotPage"];
export type BodyPhoto = components["schemas"]["BodyPhoto"];
export type BodyPose = BodyPhoto["pose"];
export type BodyMetric = components["schemas"]["BodySeries"]["metric"];
export type BodyMetrics = BodySnapshot["metrics"];
export type BodySeries = components["schemas"]["BodySeries"];
export type BodyRange = BodySeries["range"];
export type BodyTrend = NonNullable<BodySeries["trend"]>;
export type BodyComparison = components["schemas"]["BodyComparison"];
export type BodyDelta = BodyComparison["deltas"][number];
export type BodySettingsResponse = components["schemas"]["BodySettingsResponse"];
export type BodySettings = BodySettingsResponse["settings"];
export type BodySettingsUpdate = components["schemas"]["BodySettingsRequest"];
export type BodyCatalogEntry = BodySettingsResponse["catalog"][number];
export type BodyVisibility = BodySnapshot["visibility"];
export type WeightDisplay = BodySettings["weight_display"];
export type BodyUnits = BodySettings["units"];
export type CompareMode = BodySettings["compare_mode"];
export type BodySnapshotCreate = components["schemas"]["BodySnapshotCreateRequest"];
export type BodySnapshotUpdate = components["schemas"]["BodySnapshotUpdateRequest"];
export type BodyPhotoUploadRequest = components["schemas"]["BodyPhotoUploadRequest"];
export type HealthConsents = components["schemas"]["HealthConsents"];
export type HealthConsent = HealthConsents["consents"][number];
export type BodyAccessLogEntry = components["schemas"]["BodyAccessLog"]["entries"][number];
export type BodyShareRequest = components["schemas"]["BodyShareRequest"];
export type BodyShareAudience = BodyShareRequest["audience"];
export type BodyPhotosDeleted = components["schemas"]["BodyPhotosDeleted"];

export const BODY_KEY = ["my", "body"] as const;
export const BODY_SETTINGS_KEY = [...BODY_KEY, "settings"] as const;
export const BODY_SNAPSHOTS_KEY = [...BODY_KEY, "snapshots"] as const;
export const BODY_CONSENTS_KEY = [...BODY_KEY, "consents"] as const;

const id = (value: string) => encodeURIComponent(value);

function query(params: Record<string, string | number | null | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) if (value !== null && value !== undefined && value !== "") search.set(key, String(value));
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function fetchBodySnapshots(token: string, params: { cursor?: string | null; limit?: number } = {}) {
  return apiRequest<BodySnapshotPage>(`/me/body/snapshots${query(params)}`, { token });
}

export async function fetchBodySnapshot(token: string, snapshotId: string) {
  return (await apiRequest<{ snapshot: BodySnapshot }>(`/me/body/snapshots/${id(snapshotId)}`, { token })).snapshot;
}

export async function createBodySnapshot(token: string, body: BodySnapshotCreate) {
  return (await apiRequest<{ snapshot: BodySnapshot }>("/me/body/snapshots", { method: "POST", token, body })).snapshot;
}

export async function updateBodySnapshot(token: string, snapshotId: string, body: BodySnapshotUpdate) {
  return (await apiRequest<{ snapshot: BodySnapshot }>(`/me/body/snapshots/${id(snapshotId)}`, { method: "PATCH", token, body })).snapshot;
}

export function deleteBodySnapshot(token: string, snapshotId: string) {
  return apiRequest<void>(`/me/body/snapshots/${id(snapshotId)}`, { method: "DELETE", token });
}

export function fetchBodySeries(token: string, metric: BodyMetric, range: BodyRange) {
  return apiRequest<BodySeries>(`/me/body/series${query({ metric, range })}`, { token });
}

export function fetchBodyComparison(token: string, from: string, to: string) {
  return apiRequest<BodyComparison>(`/me/body/compare${query({ from, to })}`, { token });
}

export function requestBodyPhotoUpload(token: string, body: BodyPhotoUploadRequest, signal?: AbortSignal) {
  return apiRequest<MediaUpload>("/me/body/photos/uploads", { method: "POST", token, body, signal });
}

export async function attachBodyPhoto(token: string, snapshotId: string, mediaId: string, pose: BodyPose) {
  return (
    await apiRequest<{ photo: BodyPhoto }>(`/me/body/snapshots/${id(snapshotId)}/photos`, {
      method: "POST",
      token,
      body: { media_id: mediaId, pose },
    })
  ).photo;
}

export function removeBodyPhoto(token: string, snapshotId: string, photoId: string) {
  return apiRequest<void>(`/me/body/snapshots/${id(snapshotId)}/photos/${id(photoId)}`, { method: "DELETE", token });
}

export async function fetchLatestBodyPhotos(token: string) {
  return (await apiRequest<{ photos: BodyPhoto[] }>("/me/body/photos/latest", { token })).photos;
}

export function deleteAllBodyPhotos(token: string) {
  return apiRequest<BodyPhotosDeleted>("/me/body/photos", { method: "DELETE", token });
}

export function fetchBodySettings(token: string) {
  return apiRequest<BodySettingsResponse>("/me/body/settings", { token });
}

export function updateBodySettings(token: string, body: BodySettingsUpdate) {
  return apiRequest<BodySettingsResponse>("/me/body/settings", { method: "PUT", token, body });
}

export async function fetchHealthConsents(token: string) {
  return (await apiRequest<HealthConsents>("/me/body/consents", { token })).consents;
}

export async function grantHealthConsent(token: string, scope: HealthConsent["scope"]) {
  return (await apiRequest<HealthConsents>(`/me/body/consents/${scope}`, { method: "PUT", token })).consents;
}

export async function withdrawHealthConsent(token: string, scope: HealthConsent["scope"]) {
  return (await apiRequest<HealthConsents>(`/me/body/consents/${scope}`, { method: "DELETE", token })).consents;
}

export async function fetchBodyAccessLog(token: string) {
  return (await apiRequest<{ entries: BodyAccessLogEntry[] }>("/me/body/access-log", { token })).entries;
}

export async function shareBodyBeforeAfter(token: string, body: BodyShareRequest) {
  return (await apiRequest<{ post: CommunityPost }>("/me/body/share", { method: "POST", token, body })).post;
}

/** A coach's read of a client's shared snapshots (every read is logged for the member). */
export function fetchClientBodySnapshots(token: string, clientUserId: string, params: { cursor?: string | null; limit?: number } = {}) {
  return apiRequest<BodySnapshotPage>(`/staff/clients/${id(clientUserId)}/body${query(params)}`, { token });
}

export async function fetchClientBodySnapshot(token: string, clientUserId: string, snapshotId: string) {
  return (
    await apiRequest<{ snapshot: BodySnapshot }>(`/staff/clients/${id(clientUserId)}/body/snapshots/${id(snapshotId)}`, { token })
  ).snapshot;
}
