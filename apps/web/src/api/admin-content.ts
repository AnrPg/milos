import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// ADR-098 on-demand video: staff manage external video links.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;

type VideosResponse = Json<operations["PaleeWeb.AdminContentController.index"]["responses"][200]>;
type VideoResponse = Json<operations["PaleeWeb.AdminContentController.update"]["responses"][200]>;

export type ContentVideo = VideosResponse["videos"][number];
export type ContentVideoInput = NonNullable<
  operations["PaleeWeb.AdminContentController.create"]["requestBody"]
>["content"]["application/json"];

export async function fetchAdminVideos(token: string) {
  const response = await apiRequest<VideosResponse>("/admin/videos", { token });
  return response.videos;
}

export async function createAdminVideo(token: string, body: ContentVideoInput) {
  const response = await apiRequest<VideoResponse>("/admin/videos", { method: "POST", token, body });
  return response.video;
}

export async function updateAdminVideo(token: string, id: string, body: ContentVideoInput) {
  const response = await apiRequest<VideoResponse>(`/admin/videos/${id}`, { method: "PATCH", token, body });
  return response.video;
}

export async function setAdminVideoPublished(token: string, id: string, published: boolean) {
  const response = await apiRequest<VideoResponse>(`/admin/videos/${id}/publish`, {
    method: "POST",
    token,
    body: { published },
  });
  return response.video;
}

export async function archiveAdminVideo(token: string, id: string) {
  const response = await apiRequest<VideoResponse>(`/admin/videos/${id}/archive`, { method: "POST", token });
  return response.video;
}
