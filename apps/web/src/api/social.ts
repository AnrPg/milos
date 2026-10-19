import { apiRequest } from "@/api/client";
import type { CommunityPost } from "@/api/community";
import type { components } from "@/api/generated/schema";

/**
 * Social (ADR-142, P2-M2): follows of people and boxes, profile posts with
 * their audiences, a person's profile and the signed-in parts of a box page.
 * All personal: none of these go through a gym.
 */
export type FollowStatus = components["schemas"]["FollowStatusResponse"]["status"];
export type FollowTargetType = components["schemas"]["FollowRequest"]["target_type"];
export type FollowPage = components["schemas"]["FollowPage"];
export type FollowEntry = FollowPage["entries"][number];
export type SocialSummary = components["schemas"]["SocialSummary"];
export type PersonProfile = components["schemas"]["PersonProfile"];
export type PersonPostsPage = components["schemas"]["PersonPostsResponse"];
export type ProfilePostCreate = components["schemas"]["ProfilePostCreateRequest"];
export type ProfileAudience = ProfilePostCreate["audience"];
export type PublicBoxPage = components["schemas"]["PublicBoxResponse"];
export type PublicBoxSchedule = components["schemas"]["PublicBoxScheduleResponse"];
export type PublicBoxPosts = components["schemas"]["PublicBoxPostsResponse"];

export const SOCIAL_KEY = ["social"] as const;
export const SUMMARY_KEY = ["social", "summary"] as const;
export const REQUESTS_KEY = ["social", "requests"] as const;
export const followKey = (type: FollowTargetType, id: string) => ["social", "follow", type, id] as const;
export const personKey = (id: string) => ["social", "person", id] as const;

export function fetchSocialSummary(token: string) {
  return apiRequest<SocialSummary>("/me/social", { token });
}

export async function follow(token: string, targetType: FollowTargetType, targetId: string) {
  const data = await apiRequest<{ status: FollowStatus }>("/me/follows", {
    method: "POST",
    token,
    body: { target_type: targetType, target_id: targetId },
  });
  return data.status;
}

export async function unfollow(token: string, targetType: FollowTargetType, targetId: string) {
  const data = await apiRequest<{ status: FollowStatus }>(`/me/follows/${targetType}/${targetId}`, {
    method: "DELETE",
    token,
  });
  return data.status;
}

export async function fetchFollowStatus(token: string, targetType: FollowTargetType, targetId: string) {
  const data = await apiRequest<{ status: FollowStatus }>(`/me/follows/${targetType}/${targetId}`, { token });
  return data.status;
}

function paged(path: string, cursor: string | null, extra: Record<string, string> = {}) {
  const query = new URLSearchParams(extra);
  if (cursor) query.set("cursor", cursor);
  const search = query.toString();
  return search ? `${path}?${search}` : path;
}

export function fetchFollowRequests(token: string, cursor: string | null = null) {
  return apiRequest<FollowPage>(paged("/me/follow-requests", cursor), { token });
}

export function acceptFollowRequest(token: string, followId: string) {
  return apiRequest<void>(`/me/follow-requests/${followId}/accept`, { method: "POST", token });
}

export function declineFollowRequest(token: string, followId: string) {
  return apiRequest<void>(`/me/follow-requests/${followId}`, { method: "DELETE", token });
}

export function fetchFollowers(token: string, cursor: string | null = null) {
  return apiRequest<FollowPage>(paged("/me/followers", cursor), { token });
}

export function removeFollower(token: string, followId: string) {
  return apiRequest<void>(`/me/followers/${followId}`, { method: "DELETE", token });
}

export function fetchFollowing(token: string, type: "user" | "organization", cursor: string | null = null) {
  return apiRequest<FollowPage>(paged("/me/following", cursor, { type }), { token });
}

export function fetchPerson(token: string, id: string) {
  return apiRequest<PersonProfile>(`/people/${id}`, { token });
}

export function fetchPersonPosts(token: string, id: string, cursor: string | null = null) {
  return apiRequest<PersonPostsPage>(paged(`/people/${id}/posts`, cursor), { token });
}

export async function createProfilePost(token: string, body: ProfilePostCreate) {
  const data = await apiRequest<{ post: CommunityPost }>("/profile-posts", { method: "POST", token, body });
  return data.post;
}

export function fetchPublicBox(slug: string) {
  return apiRequest<PublicBoxPage>(`/public/boxes/${encodeURIComponent(slug)}`);
}

export function fetchBoxSchedule(token: string, slug: string, window?: { startAt: string; endAt: string }) {
  const query: Record<string, string> = window ? { start_at: window.startAt, end_at: window.endAt } : {};
  return apiRequest<PublicBoxSchedule>(paged(`/boxes/${encodeURIComponent(slug)}/schedule`, null, query), { token });
}

export function fetchBoxPosts(token: string, slug: string, cursor: string | null = null) {
  return apiRequest<PublicBoxPosts>(paged(`/boxes/${encodeURIComponent(slug)}/posts`, cursor), { token });
}
