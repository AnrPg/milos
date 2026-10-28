import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * In-app walkthroughs (ADR-193): the server keeps each person's progress, so
 * a guide is offered once, resumes where it was left and shows as done on
 * every device. The guides themselves (steps and copy) live in lib/guides.
 */
export type GuideProgress = components["schemas"]["GuideProgress"];
export type GuideProgressList = components["schemas"]["GuideProgressList"];
export type GuideProgressUpdate = components["schemas"]["GuideProgressUpdate"];
export type GuideStatus = GuideProgress["status"];

export const guideProgressKey = () => ["me", "guides"] as const;

export function fetchGuideProgress(token: string) {
  return apiRequest<GuideProgressList>("/me/guides", { token, scope: "account" });
}

export function putGuideProgress(token: string, guideId: string, body: GuideProgressUpdate) {
  return apiRequest<GuideProgress>(`/me/guides/${encodeURIComponent(guideId)}`, {
    token,
    scope: "account",
    method: "PUT",
    body,
  });
}

export function resetGuideProgress(token: string, guideId: string) {
  return apiRequest<GuideProgressList>(`/me/guides/${encodeURIComponent(guideId)}`, {
    token,
    scope: "account",
    method: "DELETE",
  });
}
