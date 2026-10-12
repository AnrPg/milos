import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type VideosResponse =
  paths["/api/org/{organization_slug}/me/videos"]["get"]["responses"][200]["content"]["application/json"];
type ProgressResponse =
  paths["/api/org/{organization_slug}/me/progress"]["get"]["responses"][200]["content"]["application/json"];

export type OnDemandVideo = VideosResponse["videos"][number];
export type ProgressStats = ProgressResponse["progress"];
export type ProgressWeek = ProgressStats["weekly"][number];
export type ScoreHistorySeries = ProgressStats["score_history"][number];

/** Published on-demand videos included in my package (ADR-098). */
export async function fetchMyVideos(token: string): Promise<OnDemandVideo[]> {
  const data = await apiRequest<VideosResponse>("/me/videos", { token });
  return data.videos;
}

/** Advanced statistics of my own training (ADR-098). */
export async function fetchMyProgress(token: string): Promise<ProgressStats> {
  const data = await apiRequest<ProgressResponse>("/me/progress", { token });
  return data.progress;
}
export type PRTimelineEntry = ProgressStats["pr_timeline"][number];
