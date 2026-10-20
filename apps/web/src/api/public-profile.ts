import { apiRequest } from "@/api/client";

/** A stored image (ADR-148); `url` is stable for public media. */
export type MediaItem = {
  id: string;
  purpose: "body_photo" | "box_photo" | "post_photo";
  status: "pending" | "ready";
  content_type: string;
  width: number | null;
  height: number | null;
  url: string | null;
};

/** A staff member shown, or offered, as a coach on the public page (board 4 Q4). */
export type BoxCoach = { id: string; nickname: string | null; avatar_url: string | null };

/** The draft of the gym's public «Σχετικά» (ADR-142, plan §5a board 3). */
export type BoxPublicProfile = {
  about: string | null;
  disciplines: string[];
  audiences: string[];
  amenities: string[];
  services: string[];
  languages: string[];
  cover: MediaItem | null;
  photos: MediaItem[];
  /** The coaches the page shows, in the gym's staff order. */
  coaches: BoxCoach[];
  /** The gym's staff the owner may pick from. */
  coach_candidates: BoxCoach[];
  published: boolean;
  published_at: string | null;
  /** The draft differs from what visitors see. */
  unpublished_changes: boolean;
  /** What the draft still needs before «Δημοσίευση». */
  missing: Array<"about" | "disciplines">;
  lock_version: number;
};

export type BoxPublicProfileDraft = Partial<
  Pick<BoxPublicProfile, "about" | "disciplines" | "audiences" | "amenities" | "services" | "languages">
> & { cover_photo_id?: string | null; photo_ids?: string[]; coach_ids?: string[]; lock_version?: number };

/** The canonical tag lists (board 3b); keys only, translated in `BoxTags`. */
export type BoxVocabulary = {
  discipline_groups: Array<{ key: string; items: string[] }>;
  audiences: string[];
  amenities: string[];
  services: string[];
};

export type TagList = "disciplines" | "audiences" | "amenities" | "services";

const BASE = "/admin/public-profile";

export async function getPublicProfile(token: string) {
  return (await apiRequest<{ profile: BoxPublicProfile }>(BASE, { token })).profile;
}

export async function saveProfileDraft(token: string, draft: BoxPublicProfileDraft) {
  return (await apiRequest<{ profile: BoxPublicProfile }>(BASE, { method: "PUT", token, body: draft })).profile;
}

export async function publishProfile(token: string, lockVersion: number) {
  return (
    await apiRequest<{ profile: BoxPublicProfile }>(`${BASE}/publish`, {
      method: "POST",
      token,
      body: { lock_version: lockVersion },
    })
  ).profile;
}

export async function unpublishProfile(token: string) {
  return (await apiRequest<{ profile: BoxPublicProfile }>(`${BASE}/unpublish`, { method: "POST", token })).profile;
}

export async function suggestTag(token: string, list: TagList, name: string) {
  return (
    await apiRequest<{ suggestion: { id: string; status: string } }>(`${BASE}/suggestions`, {
      method: "POST",
      token,
      body: { list, name },
    })
  ).suggestion;
}

export async function getBoxVocabulary() {
  return apiRequest<BoxVocabulary>("/box-vocabulary");
}

type PhotoUpload = { media_id: string; upload_url: string; required_headers: Record<string, string>; max_bytes: number };

/** `organizationSlug` targets one box explicitly (an event cover from the member app); else the selected gym. */
const photosBase = (organizationSlug?: string | null) =>
  organizationSlug ? `/org/${encodeURIComponent(organizationSlug)}${BASE}` : BASE;

export async function requestPhotoUpload(token: string, contentType: string, byteSize: number, organizationSlug?: string | null) {
  return apiRequest<PhotoUpload>(`${photosBase(organizationSlug)}/photos`, {
    method: "POST",
    token,
    body: { content_type: contentType, byte_size: byteSize },
  });
}

export async function completePhoto(token: string, mediaId: string, organizationSlug?: string | null) {
  return (await apiRequest<{ media: MediaItem }>(`${photosBase(organizationSlug)}/photos/${mediaId}/complete`, { method: "POST", token }))
    .media;
}

/** A tag an owner could not find (board 3b Q5), waiting for platform review. */
export type TagSuggestion = {
  id: string;
  list: TagList;
  name: string;
  status: "pending" | "added" | "declined";
  organization_name?: string;
  inserted_at?: string;
};

export async function listTagSuggestions(token: string) {
  return (await apiRequest<{ suggestions: TagSuggestion[] }>("/platform/tag-suggestions", { token })).suggestions;
}

export async function resolveTagSuggestion(token: string, id: string, status: "added" | "declined") {
  await apiRequest<void>(`/platform/tag-suggestions/${id}`, { method: "PATCH", token, body: { status } });
}
