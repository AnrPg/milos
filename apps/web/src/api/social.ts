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
/** ADR-193: Buddies, people who follow only, people followed only (never overlapping). */
export type FollowGroups = components["schemas"]["FollowGroups"];
export type SocialPrivacy = components["schemas"]["SocialPrivacy"];
export type SocialPrivacyRequest = components["schemas"]["SocialPrivacyRequest"];
export type PeopleSearchResponse = components["schemas"]["PeopleSearchResponse"];
export type PeopleSearchPerson = components["schemas"]["PeopleSearchPerson"];
export type PeopleRelation = PeopleSearchPerson["relation"];
/** ADR-221: published, live boxes and independent coaches found by name. */
export type BoxSearchResponse = components["schemas"]["BoxSearchResponse"];
export type BoxSearchResult = components["schemas"]["BoxSearchResult"];

export const SOCIAL_KEY = ["social"] as const;
export const SUMMARY_KEY = ["social", "summary"] as const;
export const REQUESTS_KEY = ["social", "requests"] as const;
export const followKey = (type: FollowTargetType, id: string) => ["social", "follow", type, id] as const;
export const personKey = (id: string) => ["social", "person", id] as const;
export const peopleSearchKey = (q: string) => ["social", "people-search", q] as const;
export const boxSearchKey = (q: string) => ["social", "box-search", q] as const;

/** ADR-193 §4: the search answers only from two characters on. */
export const PEOPLE_SEARCH_MIN = 2;

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

/** `q` keeps names containing it, ignoring case and accents (board 5 Q4). */
export function fetchFollowers(token: string, cursor: string | null = null, q = "") {
  return apiRequest<FollowPage>(paged("/me/followers", cursor, q ? { q } : {}), { token });
}

export function removeFollower(token: string, followId: string) {
  return apiRequest<void>(`/me/followers/${followId}`, { method: "DELETE", token });
}

export function fetchFollowing(token: string, type: "user" | "organization", cursor: string | null = null, q = "") {
  return apiRequest<FollowPage>(paged("/me/following", cursor, q ? { type, q } : { type }), { token });
}

/** ADR-193 §1: people you follow who follow you back; `q` filters names as above. */
export function fetchBuddies(token: string, cursor: string | null = null, q = "") {
  return apiRequest<FollowPage>(paged("/me/buddies-list", cursor, q ? { q } : {}), { token });
}

/** ADR-193 §4: anyone on Palee who isn't private, plus the people you already know. */
export function searchPeople(token: string, q: string) {
  return apiRequest<PeopleSearchResponse>(`/people-search?${new URLSearchParams({ q })}`, { token });
}

/** ADR-221: boxes and coaches by name, from two characters on like people. */
export function searchBoxes(token: string, q: string) {
  return apiRequest<BoxSearchResponse>(`/box-search?${new URLSearchParams({ q })}`, { token });
}

/** ADR-193 §2: going public also accepts the requests that are waiting. */
export function setSocialPrivacy(token: string, body: SocialPrivacyRequest) {
  return apiRequest<SocialPrivacy>("/me/social/privacy", { method: "PUT", token, body });
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

export type BookingSharing = components["schemas"]["BookingSharing"];

/** Board 5 Q6: show followers the classes you book (the «Φίλοι» chip), or stop. */
export function setBookingSharing(token: string, enabled: boolean) {
  return apiRequest<BookingSharing>("/me/social/booking-sharing", { method: "PUT", token, body: { enabled } });
}
