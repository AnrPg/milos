import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Photos and videos in posts (ADR-157): what the server takes, one presigned
 * upload per picked file, its completion, its state while it processes, its
 * alternative text (with an AI suggestion), and the card a PR makes in a
 * post (to prefill compose right after the PR is logged).
 */
export type PostMedia = components["schemas"]["PostMedia"];
export type MediaCapabilities = components["schemas"]["PostMediaCapabilities"];
export type MediaUpload = components["schemas"]["MediaUpload"];
export type MediaUploadRequest = components["schemas"]["PostMediaUploadRequest"];
export type MediaRecord = components["schemas"]["Media"];
export type MediaContentType = MediaUploadRequest["content_type"];
export type PostAttachmentPreview = components["schemas"]["PostAttachmentPreview"];
export type ShareableAttachmentType = "training_log_entry" | "workout_execution" | "pr";

export const MEDIA_CAPABILITIES_KEY = ["media", "capabilities"] as const;

const id = (value: string) => encodeURIComponent(value);

export function fetchMediaCapabilities(token: string) {
  return apiRequest<MediaCapabilities>("/me/media/capabilities", { token });
}

export function requestMediaUpload(token: string, body: MediaUploadRequest, signal?: AbortSignal) {
  return apiRequest<MediaUpload>("/me/media/uploads", { method: "POST", token, body, signal });
}

export async function completeMediaUpload(token: string, mediaId: string, signal?: AbortSignal) {
  return (await apiRequest<{ media: MediaRecord }>(`/me/media/${id(mediaId)}/complete`, { method: "POST", token, signal })).media;
}

export async function fetchMedia(token: string, mediaId: string, signal?: AbortSignal) {
  return (await apiRequest<{ media: MediaRecord }>(`/me/media/${id(mediaId)}`, { token, signal })).media;
}

export async function updateMediaAltText(token: string, mediaId: string, altText: string | null) {
  return (
    await apiRequest<{ media: MediaRecord }>(`/me/media/${id(mediaId)}`, {
      method: "PATCH",
      token,
      body: { alt_text: altText },
    })
  ).media;
}

/** A one-sentence description to offer; never saved by the server. */
export async function suggestMediaAltText(token: string, mediaId: string, locale?: string) {
  return (
    await apiRequest<{ suggestion: string }>(`/me/media/${id(mediaId)}/alt-text-suggestion`, {
      method: "POST",
      token,
      body: locale ? { locale } : {},
    })
  ).suggestion;
}

/** Takes an upload back out of the compose (only while it is not in a post). */
export function discardMedia(token: string, mediaId: string) {
  return apiRequest<void>(`/me/media/${id(mediaId)}`, { method: "DELETE", token });
}

export function fetchPostAttachment(token: string, type: ShareableAttachmentType, attachmentId: string) {
  return apiRequest<PostAttachmentPreview>(`/me/post-attachments/${type}/${id(attachmentId)}`, { token });
}
