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
export type WodTodayCard = components["schemas"]["WodTodayCard"];
export type WodLeaderboardEntry = components["schemas"]["WodLeaderboardEntry"];

export const NOTIFY_LEVELS: NotifyLevel[] = ["all", "announcements", "none"];
export const CLUBS_KEY = ["community", "clubs"] as const;
export const FEED_KEY = ["community", "feed"] as const;
export const WOD_KEY = ["community", "wod-today"] as const;

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

/**
 * Where a post's own actions live: a club post in its gym, a profile post
 * (origin `profile`, ADR-142) on the author's account.
 */
function postPath(post: Pick<CommunityPost, "id" | "origin" | "club">) {
  return post.origin === "profile" || !post.club
    ? `/profile-posts/${post.id}`
    : `${base(post.club.organization_slug)}/posts/${post.id}`;
}

function commentPath(post: Pick<CommunityPost, "origin" | "club">, id: string) {
  return post.origin === "profile" || !post.club
    ? `/profile-post-comments/${id}`
    : `${base(post.club.organization_slug)}/comments/${id}`;
}

export function deletePost(token: string, post: CommunityPost) {
  return apiRequest<void>(postPath(post), { method: "DELETE", token });
}

async function putFlag(token: string, post: CommunityPost, flag: "hidden" | "pinned" | "kudos", value: boolean) {
  const data = await apiRequest<{ post: CommunityPost }>(`${postPath(post)}/${flag}`, {
    method: "PUT",
    token,
    body: { [flag]: value },
  });
  return data.post;
}

export const setPostHidden = (token: string, post: CommunityPost, hidden: boolean) =>
  putFlag(token, post, "hidden", hidden);
export const setPostPinned = (token: string, post: CommunityPost, pinned: boolean) =>
  putFlag(token, post, "pinned", pinned);
export const setKudos = (token: string, post: CommunityPost, kudos: boolean) => putFlag(token, post, "kudos", kudos);

export async function fetchComments(token: string, post: CommunityPost) {
  const data = await apiRequest<{ comments: CommunityComment[] }>(`${postPath(post)}/comments`, { token });
  return data.comments;
}

export async function addComment(token: string, post: CommunityPost, body: string) {
  const data = await apiRequest<{ comment: CommunityComment }>(`${postPath(post)}/comments`, {
    method: "POST",
    token,
    body: { body },
  });
  return data.comment;
}

export function deleteComment(token: string, post: CommunityPost, id: string) {
  return apiRequest<void>(commentPath(post, id), { method: "DELETE", token });
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

/** The gym's #wod card for the member's local today: WOD, classes, leaderboard (D6). */
export function fetchWodToday(token: string, slug: string, timezone: string) {
  const query = new URLSearchParams({ timezone });
  return apiRequest<WodTodayCard>(`${base(slug)}/wod-today?${query.toString()}`, { token });
}
