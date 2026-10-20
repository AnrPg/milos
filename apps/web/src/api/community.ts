import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Community (ADR-138, ADR-143): the member's clubs, the feed of their posts,
 * compose, kudos, comments, moderation, member groups, open clubs, «Μέλη» and
 * reports. Reads and post actions are personal (any club the member reaches,
 * open clubs of other gyms included); group calls go to the gym that runs the
 * club.
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

export type CommunityGroup = components["schemas"]["CommunityGroup"];
export type CommunityGroupMember = components["schemas"]["CommunityGroupMember"];
export type CommunityGroupSettings = components["schemas"]["CommunityGroupSettings"];
export type CommunityGroups = components["schemas"]["CommunityGroupsResponse"];
export type GroupJoinPolicy = CommunityGroup["join_policy"];
export type GroupDraft = components["schemas"]["CommunityGroupRequest"];
export type OpenClub = components["schemas"]["CommunityOpenClub"];
export type OpenClubJoinPolicy = OpenClub["join_policy"];
export type CommunityMember = components["schemas"]["CommunityMember"];
export type Discover = components["schemas"]["CommunityDiscoverResponse"];
export type ReportRequest = components["schemas"]["CommunityReportRequest"];
export type ReportReason = ReportRequest["reason"];
export type ReportTarget = ReportRequest["target_type"];

export const REPORT_REASONS: ReportReason[] = ["spam", "harassment", "inappropriate", "other"];
export const NOTIFY_LEVELS: NotifyLevel[] = ["all", "announcements", "none"];
export const CLUBS_KEY = ["community", "clubs"] as const;
export const FEED_KEY = ["community", "feed"] as const;
export const WOD_KEY = ["community", "wod-today"] as const;
export const groupsKey = (clubId: string) => ["community", "groups", clubId] as const;
export const groupKey = (groupId: string) => ["community", "group", groupId] as const;
export const membersKey = (clubId: string, q: string) => ["community", "members", clubId, q] as const;
export const openClubKey = (clubId: string) => ["community", "open-club", clubId] as const;
export const discoverKey = (q: string) => ["community", "discover", q] as const;

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
const id = (value: string) => encodeURIComponent(value);

/** Posts in any club the member reaches go through their personal session (ADR-143). */
export async function createPost(token: string, body: PostCreate) {
  const data = await apiRequest<{ post: CommunityPost }>("/me/community/posts", { method: "POST", token, body });
  return data.post;
}

/** Where a post's own actions live: a club post, or a profile post (origin `profile`, ADR-142). */
function postPath(post: Pick<CommunityPost, "id" | "origin" | "club">) {
  return post.origin === "profile" || !post.club ? `/profile-posts/${id(post.id)}` : `/me/community/posts/${id(post.id)}`;
}

function commentPath(post: Pick<CommunityPost, "origin" | "club">, commentId: string) {
  return post.origin === "profile" || !post.club
    ? `/profile-post-comments/${id(commentId)}`
    : `/me/community/comments/${id(commentId)}`;
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

export function deleteComment(token: string, post: CommunityPost, commentId: string) {
  return apiRequest<void>(commentPath(post, commentId), { method: "DELETE", token });
}

/** Staff and group admins hide a comment; it stays visible to them, marked. */
export async function setCommentHidden(token: string, commentId: string, hidden: boolean) {
  const data = await apiRequest<{ comment: CommunityComment }>(`/me/community/comments/${id(commentId)}/hidden`, {
    method: "PUT",
    token,
    body: { hidden },
  });
  return data.comment;
}

/** How much the member hears from a club: gym clubs through the gym, open clubs personally. */
export function setNotifyLevel(token: string, club: Pick<CommunityClub, "id" | "kind" | "organization_slug">, level: NotifyLevel) {
  const path =
    club.kind === "open" || !club.organization_slug
      ? `/me/open-clubs/${id(club.id)}/notify-level`
      : `${base(club.organization_slug)}/clubs/${id(club.id)}/notify-level`;
  return apiRequest<{ club_id: string; notify_level: NotifyLevel }>(path, {
    method: "PUT",
    token,
    body: { notify_level: level },
  });
}

export function setChannelJoined(token: string, slug: string, channelId: string, joined: boolean) {
  return apiRequest<{ channel_id: string; joined: boolean }>(`${base(slug)}/channels/${id(channelId)}/membership`, {
    method: joined ? "POST" : "DELETE",
    token,
  });
}

// Member groups (board 7 Q2) --------------------------------------------------

export function fetchGroups(token: string, slug: string) {
  return apiRequest<CommunityGroups>(`${base(slug)}/groups`, { token });
}

export async function proposeGroup(token: string, slug: string, draft: GroupDraft) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups`, { method: "POST", token, body: draft });
  return data.group;
}

export async function fetchGroup(token: string, slug: string, groupId: string) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}`, { token });
  return data.group;
}

export async function updateGroup(token: string, slug: string, groupId: string, draft: Partial<GroupDraft>) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}`, {
    method: "PATCH",
    token,
    body: draft,
  });
  return data.group;
}

export async function joinGroup(token: string, slug: string, groupId: string) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}/membership`, {
    method: "POST",
    token,
  });
  return data.group;
}

/** Leaving: the last admin hands over first; the last member archives the group. */
export function leaveGroup(token: string, slug: string, groupId: string) {
  return apiRequest<{ group_id: string; outcome: "left" | "archived" }>(`${base(slug)}/groups/${id(groupId)}/membership`, {
    method: "DELETE",
    token,
  });
}

export async function answerGroupRequest(token: string, slug: string, groupId: string, userId: string, approve: boolean) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}/requests/${id(userId)}`, {
    method: "PUT",
    token,
    body: { approve },
  });
  return data.group;
}

export async function setGroupAdmin(token: string, slug: string, groupId: string, userId: string, admin: boolean) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}/admins/${id(userId)}`, {
    method: "PUT",
    token,
    body: { admin },
  });
  return data.group;
}

export async function removeGroupMember(token: string, slug: string, groupId: string, userId: string) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}/members/${id(userId)}`, {
    method: "DELETE",
    token,
  });
  return data.group;
}

export function archiveGroup(token: string, slug: string, groupId: string) {
  return apiRequest<{ group_id: string; outcome: "left" | "archived" }>(`${base(slug)}/groups/${id(groupId)}/archive`, {
    method: "POST",
    token,
  });
}

export async function reopenGroup(token: string, slug: string, groupId: string) {
  const data = await apiRequest<{ group: CommunityGroup }>(`${base(slug)}/groups/${id(groupId)}/reopen`, {
    method: "POST",
    token,
  });
  return data.group;
}

// Open clubs, «Βρες» and «Μέλη» (board 7 Q1, Q6, Q7) ------------------------

export function fetchDiscover(token: string, q: string) {
  const query = new URLSearchParams();
  if (q.trim()) query.set("q", q.trim());
  return apiRequest<Discover>(`/me/community/discover?${query.toString()}`, { token });
}

export async function fetchOpenClub(token: string, clubId: string) {
  const data = await apiRequest<{ club: OpenClub }>(`/me/open-clubs/${id(clubId)}`, { token });
  return data.club;
}

export async function setOpenClubJoined(token: string, clubId: string, joined: boolean) {
  const data = await apiRequest<{ club: OpenClub }>(`/me/open-clubs/${id(clubId)}/membership`, {
    method: joined ? "POST" : "DELETE",
    token,
  });
  return data.club;
}

export function fetchClubMembers(token: string, clubId: string, q: string) {
  const query = new URLSearchParams();
  if (q.trim()) query.set("q", q.trim());
  return apiRequest<{ club_id: string; count: number; members: CommunityMember[] }>(
    `/me/clubs/${id(clubId)}/members?${query.toString()}`,
    { token },
  );
}

// Reports (board 7 Q4) --------------------------------------------------------

export function reportItem(token: string, report: ReportRequest) {
  return apiRequest<{ reported: boolean; target_id: string; target_type: string }>("/me/community/reports", {
    method: "POST",
    token,
    body: report,
  });
}

/** Hides or shows the member from other members' «Μέλη» lists. */
export function setMemberVisibility(token: string, hidden: boolean) {
  return apiRequest<{ hidden: boolean }>("/me/social/member-visibility", { method: "PUT", token, body: { hidden } });
}

/** The gym's #wod card for the member's local today: WOD, classes, leaderboard (D6). */
export function fetchWodToday(token: string, slug: string, timezone: string) {
  const query = new URLSearchParams({ timezone });
  return apiRequest<WodTodayCard>(`${base(slug)}/wod-today?${query.toString()}`, { token });
}
