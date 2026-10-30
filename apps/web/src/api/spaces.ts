import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// Spaces of each branch, their floor plans and unavailability (ADR-202), and
// the cleaning schedule and «Σήμερα» of the cleaning log built on them.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Body<T> = T extends { requestBody: { content: { "application/json": infer B } } } ? B : never;
type Op = operations;
type SpacesOp<Name extends string> = Op[`PaleeWeb.SpacesController.${Name}` & keyof Op];
type CleaningOp<Name extends string> = Op[`PaleeWeb.CleaningController.${Name}` & keyof Op];

type IndexResponse = Json<SpacesOp<"index">["responses"][200]>;
type ShowResponse = Json<SpacesOp<"show">["responses"][200]>;
type SpaceResponse = Json<SpacesOp<"update">["responses"][200]>;
type UnavailableResponse = Json<SpacesOp<"make_unavailable">["responses"][201]>;
type FloorPlanResponse = Json<SpacesOp<"create_floor_plan">["responses"][201]>;
type UploadResponse = Json<SpacesOp<"floor_plan_upload">["responses"][200]>;
type SchedulesResponse = Json<CleaningOp<"schedules">["responses"][200]>;
type ScheduleResponse = Json<CleaningOp<"put_schedule">["responses"][200]>;
type TodayResponse = Json<CleaningOp<"today">["responses"][200]>;

export type Space = IndexResponse["spaces"][number];
export type SpaceDetail = ShowResponse["space"];
export type SpaceClass = SpaceDetail["classes"][number];
export type SpaceEquipment = SpaceDetail["equipment"][number];
export type SpaceInput = Body<SpacesOp<"create">>;
export type SpaceArea = NonNullable<Space["area"]>;
export type SpaceUnavailability = UnavailableResponse["unavailability"];
export type FloorPlan = IndexResponse["floor_plans"][number];
export type FloorPlanInput = Body<SpacesOp<"create_floor_plan">>;
export type CleaningSchedule = SchedulesResponse["schedules"][number];
export type CleaningScheduleInput = Body<CleaningOp<"put_schedule">>;
export type CleaningToday = TodayResponse;
export type CleaningDue = TodayResponse["due"][number];

export async function fetchSpaces(token: string, options: { locationId?: string; includeArchived?: boolean } = {}) {
  const search = new URLSearchParams();
  if (options.locationId) search.set("location_id", options.locationId);
  if (options.includeArchived) search.set("include_archived", "true");
  const suffix = search.size > 0 ? `?${search.toString()}` : "";
  return apiRequest<IndexResponse>(`/staff/spaces${suffix}`, { token });
}

export async function fetchSpace(token: string, id: string) {
  const response = await apiRequest<ShowResponse>(`/staff/spaces/${id}`, { token });
  return response.space;
}

export async function createSpace(token: string, body: SpaceInput) {
  const response = await apiRequest<SpaceResponse>("/staff/spaces", { method: "POST", token, body });
  return response.space;
}

export async function updateSpace(token: string, id: string, body: SpaceInput) {
  const response = await apiRequest<SpaceResponse>(`/staff/spaces/${id}`, { method: "PATCH", token, body });
  return response.space;
}

export async function archiveSpace(token: string, id: string) {
  const response = await apiRequest<SpaceResponse>(`/staff/spaces/${id}/archive`, { method: "POST", token });
  return response.space;
}

export async function restoreSpace(token: string, id: string) {
  const response = await apiRequest<SpaceResponse>(`/staff/spaces/${id}/restore`, { method: "POST", token });
  return response.space;
}

export async function makeSpaceUnavailable(token: string, id: string, body: { starts_at: string; ends_at: string; reason?: string | null }) {
  return apiRequest<UnavailableResponse>(`/staff/spaces/${id}/unavailability`, { method: "POST", token, body });
}

export async function deleteSpaceUnavailability(token: string, id: string, windowId: string) {
  await apiRequest<unknown>(`/staff/spaces/${id}/unavailability/${windowId}`, { method: "DELETE", token });
}

export async function requestFloorPlanUpload(token: string, body: { content_type: string; byte_size: number }) {
  return apiRequest<UploadResponse>("/staff/floor-plans/uploads", { method: "POST", token, body });
}

export async function completeFloorPlanUpload(token: string, mediaId: string) {
  await apiRequest<unknown>(`/staff/floor-plans/uploads/${mediaId}/complete`, { method: "POST", token });
}

export async function createFloorPlan(token: string, body: FloorPlanInput) {
  const response = await apiRequest<FloorPlanResponse>("/staff/floor-plans", { method: "POST", token, body });
  return response.floor_plan;
}

export async function updateFloorPlan(token: string, id: string, body: FloorPlanInput) {
  const response = await apiRequest<FloorPlanResponse>(`/staff/floor-plans/${id}`, { method: "PATCH", token, body });
  return response.floor_plan;
}

export async function deleteFloorPlan(token: string, id: string) {
  await apiRequest<unknown>(`/staff/floor-plans/${id}`, { method: "DELETE", token });
}

export async function fetchCleaningSchedules(token: string) {
  const response = await apiRequest<SchedulesResponse>("/staff/cleaning/schedules", { token });
  return response.schedules;
}

export async function putCleaningSchedule(token: string, spaceId: string, body: CleaningScheduleInput) {
  const response = await apiRequest<ScheduleResponse>(`/staff/cleaning/schedules/${spaceId}`, { method: "PUT", token, body });
  return response.schedule;
}

export async function deleteCleaningSchedule(token: string, spaceId: string) {
  await apiRequest<unknown>(`/staff/cleaning/schedules/${spaceId}`, { method: "DELETE", token });
}

export async function fetchCleaningToday(token: string) {
  return apiRequest<TodayResponse>("/staff/cleaning/today", { token });
}

// ADR-290: the gym's space settings, room photos, the visual cleaning
// checklist and the room of a class on the floor plan.

type SettingsResponse = Json<SpacesOp<"settings">["responses"][200]>;
type PhotoResponse = Json<SpacesOp<"add_photo">["responses"][201]>;
type PointResponse = Json<SpacesOp<"add_point">["responses"][201]>;
type PhotosOrderResponse = Json<SpacesOp<"order_photos">["responses"][200]>;
type PointsOrderResponse = Json<SpacesOp<"order_points">["responses"][200]>;

export type SpaceSettings = SettingsResponse["settings"];
export type SpacePhoto = PhotoResponse["photo"];
export type CleaningPoint = PointResponse["point"];
export type SpacePhotoInput = Body<SpacesOp<"add_photo">>;
export type CleaningPointInput = Body<SpacesOp<"add_point">>;
export type PhotoKind = "photos" | "points";

export async function fetchSpaceSettings(token: string) {
  const response = await apiRequest<SettingsResponse>("/staff/space-settings", { token });
  return response.settings;
}

export async function putSpaceSettings(token: string, body: { floor_plans_in_classes: boolean }) {
  const response = await apiRequest<SettingsResponse>("/staff/space-settings", { method: "PUT", token, body });
  return response.settings;
}

const UPLOAD_PATH: Record<PhotoKind | "machine", string> = {
  photos: "/staff/space-photos/uploads",
  points: "/staff/cleaning-photos/uploads",
  machine: "/staff/inventory/machine-photos/uploads",
};

/** Reserves, uploads and verifies one photo; returns its media id. */
export async function uploadRoomPhoto(
  token: string,
  kind: PhotoKind | "machine",
  photo: { blob: Blob; contentType: string },
  put: (url: string, blob: Blob, headers: UploadResponse["required_headers"]) => Promise<unknown>,
) {
  const reserved = await apiRequest<UploadResponse>(UPLOAD_PATH[kind], {
    method: "POST",
    token,
    body: { content_type: photo.contentType, byte_size: photo.blob.size },
  });
  await put(reserved.upload_url, photo.blob, reserved.required_headers);
  await apiRequest<unknown>(`${UPLOAD_PATH[kind]}/${reserved.media_id}/complete`, { method: "POST", token });
  return reserved.media_id;
}

export async function addSpacePhoto(token: string, spaceId: string, body: SpacePhotoInput) {
  const response = await apiRequest<PhotoResponse>(`/staff/spaces/${spaceId}/photos`, { method: "POST", token, body });
  return response.photo;
}

export async function updateSpacePhoto(token: string, id: string, body: SpacePhotoInput) {
  const response = await apiRequest<PhotoResponse>(`/staff/space-photos/${id}`, { method: "PATCH", token, body });
  return response.photo;
}

export async function deleteSpacePhoto(token: string, id: string) {
  await apiRequest<unknown>(`/staff/space-photos/${id}`, { method: "DELETE", token });
}

export async function orderSpacePhotos(token: string, spaceId: string, ids: string[]) {
  const response = await apiRequest<PhotosOrderResponse>(`/staff/spaces/${spaceId}/photos/order`, { method: "PUT", token, body: { ids } });
  return response.photos;
}

export async function addCleaningPoint(token: string, spaceId: string, body: CleaningPointInput) {
  const response = await apiRequest<PointResponse>(`/staff/spaces/${spaceId}/cleaning-points`, { method: "POST", token, body });
  return response.point;
}

export async function updateCleaningPoint(token: string, id: string, body: CleaningPointInput) {
  const response = await apiRequest<PointResponse>(`/staff/cleaning-points/${id}`, { method: "PATCH", token, body });
  return response.point;
}

export async function deleteCleaningPoint(token: string, id: string) {
  await apiRequest<unknown>(`/staff/cleaning-points/${id}`, { method: "DELETE", token });
}

export async function orderCleaningPoints(token: string, spaceId: string, ids: string[]) {
  const response = await apiRequest<PointsOrderResponse>(`/staff/spaces/${spaceId}/cleaning-points/order`, { method: "PUT", token, body: { ids } });
  return response.points;
}
