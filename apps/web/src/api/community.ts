import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Community (ADR-138): the member's clubs, the feed of their posts, compose,
 * kudos, comments and staff moderation. Reads are personal (across every gym
 * the member belongs to); writes go to the gym that runs the club.
 */
export type CommunityClub = components["schemas"]["CommunityClub"];
export type CommunityChannel = components["schemas"]["CommunityChannel"];
export type ChannelKind = CommunityChannel["kind"];
export type NotifyLevel = CommunityClub["notify_level"];
export type CommunityPost = components["schemas"]["CommunityPost"];
export type CommunityFeedPage = components["schemas"]["CommunityFeedPage"];
export type CommunityComment = components["schemas"]["CommunityComment"];
export type PostCreate = components["schemas"]["CommunityPostCreateRequest"];
export type AttachmentType = NonNullable<PostCreate["attachment_type"]>;

export const NOTIFY_LEVELS: NotifyLevel[] = ["all", "announcements", "none"];
export const CLUBS_KEY = ["community", "clubs"] as const;
export const FEED_KEY = ["community", "feed"] as const;

export type FeedFilter = { clubId?: string | null; channelId?: string | null; mine?: boolean };

export async function fetchMyClubs(token: string) {
  const data = await apiRequest<{ clubs: CommunityClub[] }>("/me/clubs", { token });
  return data.clubs;
}

export function fetchFeed(token: string, filter: FeedFilter, cursor: string | null, limit = 20) {
  const query = new URLSearchParams();
  if (filter.clubId) query.set("club_id", filter.clubId);
  if (filter.channelId) query.set("channel_id", filter.channelId);
  if (filter.mine) query.set("mine", "true");
  if (cursor) query.set("cursor", cursor);
  query.set("limit", String(limit));
  return apiRequest<CommunityFeedPage>(`/me/feed?${query.toString()}`, { token });
}

const base = (slug: string) => `/org/${slug}/community`;

export async function createPost(token: string, slug: string, body: PostCreate) {
  const data = await apiRequest<{ post: CommunityPost }>(`${base(slug)}/posts`, { method: "POST", token, body });
  return data.post;
}

export function deletePost(token: string, slug: string, id: string) {
  return apiRequest<void>(`${base(slug)}/posts/${id}`, { method: "DELETE", token });
}

async function putFlag(token: string, slug: string, id: string, flag: "hidden" | "pinned" | "kudos", value: boolean) {
  const data = await apiRequest<{ post: CommunityPost }>(`${base(slug)}/posts/${id}/${flag}`, {
    method: "PUT",
    token,
    body: { [flag]: value },
  });
  return data.post;
}

export const setPostHidden = (token: string, slug: string, id: string, hidden: boolean) =>
  putFlag(token, slug, id, "hidden", hidden);
export const setPostPinned = (token: string, slug: string, id: string, pinned: boolean) =>
  putFlag(token, slug, id, "pinned", pinned);
export const setKudos = (token: string, slug: string, id: string, kudos: boolean) =>
  putFlag(token, slug, id, "kudos", kudos);

export async function fetchComments(token: string, slug: string, postId: string) {
  const data = await apiRequest<{ comments: CommunityComment[] }>(`${base(slug)}/posts/${postId}/comments`, { token });
  return data.comments;
}

export async function addComment(token: string, slug: string, postId: string, body: string) {
  const data = await apiRequest<{ comment: CommunityComment }>(`${base(slug)}/posts/${postId}/comments`, {
    method: "POST",
    token,
    body: { body },
  });
  return data.comment;
}

export function deleteComment(token: string, slug: string, id: string) {
  return apiRequest<void>(`${base(slug)}/comments/${id}`, { method: "DELETE", token });
}

export function setNotifyLevel(token: string, slug: string, clubId: string, level: NotifyLevel) {
  return apiRequest<{ club_id: string; notify_level: NotifyLevel }>(`${base(slug)}/clubs/${clubId}/notify-level`, {
    method: "PUT",
    token,
    body: { notify_level: level },
  });
}

export function setChannelJoined(token: string, slug: string, channelId: string, joined: boolean) {
  return apiRequest<{ channel_id: string; joined: boolean }>(`${base(slug)}/channels/${channelId}/membership`, {
    method: joined ? "POST" : "DELETE",
    token,
  });
}
