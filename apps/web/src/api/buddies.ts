import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Εγώ › Buddy για στήριξη (ADR-160): one or two trusted people with mutual
 * acceptance, «Χρειάζομαι στήριξη» with a 5-second undo, the buddy's quick
 * replies and the pair's own conversation, quiet hours and phone sharing,
 * and the member's grants for the coach's weekly wellness summary.
 */
export type BuddyOverview = components["schemas"]["BuddyOverview"];
export type BuddyLink = components["schemas"]["BuddyLink"];
export type BuddyPerson = components["schemas"]["BuddyPerson"];
export type BuddyStatus = BuddyLink["status"];
export type BuddySettings = components["schemas"]["BuddySettings"];
export type BuddySettingsRequest = components["schemas"]["BuddySettingsRequest"];
export type BuddyQuietHours = NonNullable<BuddySettings["quiet_hours"]>;
export type BuddyCandidate = components["schemas"]["BuddyCandidates"]["candidates"][number];
export type BuddyRelation = BuddyCandidate["relation"];
export type BuddyInviteLink = components["schemas"]["BuddyInviteLinkResponse"];
export type BuddyInvitePreview = components["schemas"]["BuddyInvitePreview"];
export type BuddyMessage = components["schemas"]["BuddyMessage"];
export type BuddyMessagePage = components["schemas"]["BuddyMessagePage"];
export type SupportRequest = components["schemas"]["SupportRequest"];
export type SupportReply = components["schemas"]["SupportReply"];
export type SupportReplyKind = SupportReply["kind"];
export type SupportQuickReply = Exclude<SupportReplyKind, "text">;
export type SupportReplyResponse = components["schemas"]["SupportReplyResponse"];
export type SupportRecipient = NonNullable<SupportRequest["recipients"]>[number];
export type SupportNudge = NonNullable<SupportRequest["nudge"]>;
export type WellnessSummarySharing = components["schemas"]["WellnessSummarySharing"];
export type WellnessSummarySharingRequest = components["schemas"]["WellnessSummarySharingRequest"];
export type WellnessAccessLogEntry = components["schemas"]["WellnessAccessLog"]["entries"][number];
export type ClientWellnessSummary = components["schemas"]["ClientWellnessSummary"];

export const BUDDIES_KEY = ["my", "buddies"] as const;
export const SUPPORT_REQUESTS_KEY = ["my", "support-requests"] as const;
export const WELLNESS_SHARING_KEY = ["my", "wellness-summary-sharing"] as const;
export const QUICK_REPLIES: SupportQuickReply[] = ["here", "walk", "call"];

const id = (value: string) => encodeURIComponent(value);

export function fetchBuddies(token: string) {
  return apiRequest<BuddyOverview>("/me/buddies", { token });
}

export async function fetchBuddyCandidates(token: string, term: string) {
  const q = term.trim();
  const data = await apiRequest<{ candidates?: BuddyCandidate[] }>(`/me/buddies/candidates${q ? `?q=${encodeURIComponent(q)}` : ""}`, { token });
  return data.candidates ?? [];
}

export async function inviteBuddy(token: string, userId: string) {
  return (await apiRequest<{ link: BuddyLink }>("/me/buddies", { method: "POST", token, body: { user_id: userId } })).link;
}

export function createBuddyInviteLink(token: string) {
  return apiRequest<BuddyInviteLink>("/me/buddies/invite-links", { method: "POST", token });
}

export async function updateBuddyLink(token: string, linkId: string, body: { receives_weekly_summary: boolean }) {
  return (await apiRequest<{ link: BuddyLink }>(`/me/buddies/${id(linkId)}`, { method: "PATCH", token, body })).link;
}

export async function changeBuddyLink(token: string, linkId: string, action: "accept" | "decline" | "leave") {
  return (await apiRequest<{ link: BuddyLink }>(`/me/buddies/${id(linkId)}/${action}`, { method: "POST", token })).link;
}

export async function fetchBuddySettings(token: string) {
  return (await apiRequest<{ settings: BuddySettings }>("/me/buddies/settings", { token })).settings;
}

export async function updateBuddySettings(token: string, body: BuddySettingsRequest) {
  return (await apiRequest<{ settings: BuddySettings }>("/me/buddies/settings", { method: "PUT", token, body })).settings;
}

export function fetchBuddyMessages(token: string, linkId: string, cursor?: string | null) {
  const search = cursor ? `?cursor=${encodeURIComponent(cursor)}` : "";
  return apiRequest<BuddyMessagePage>(`/me/buddies/${id(linkId)}/messages${search}`, { token });
}

export async function sendBuddyMessage(token: string, linkId: string, body: string) {
  return (await apiRequest<{ message: BuddyMessage }>(`/me/buddies/${id(linkId)}/messages`, { method: "POST", token, body: { body } })).message;
}

export function markBuddyMessagesRead(token: string, linkId: string) {
  return apiRequest<{ read: number }>(`/me/buddies/${id(linkId)}/messages/read`, { method: "POST", token });
}

/** Public: who invites and whether the link still works. */
export function fetchBuddyInvite(token: string | null, inviteToken: string) {
  return apiRequest<BuddyInvitePreview>(`/buddy-invites/${id(inviteToken)}`, token ? { token } : {});
}

/** Claiming the link is the acceptance. */
export async function claimBuddyInvite(token: string, inviteToken: string) {
  return (await apiRequest<{ link: BuddyLink }>(`/me/buddy-invites/${id(inviteToken)}/claim`, { method: "POST", token })).link;
}

export async function fetchSupportRequests(token: string, role: "sent" | "received") {
  const data = await apiRequest<{ support_requests?: SupportRequest[] }>(`/me/support-requests?role=${role}`, { token });
  return data.support_requests ?? [];
}

export async function fetchSupportRequest(token: string, requestId: string) {
  return (await apiRequest<{ support_request: SupportRequest }>(`/me/support-requests/${id(requestId)}`, { token })).support_request;
}

export async function sendSupportRequest(token: string, message: string | null) {
  return (await apiRequest<{ support_request: SupportRequest }>("/me/support-requests", { method: "POST", token, body: { message } }))
    .support_request;
}

export async function undoSupportRequest(token: string, requestId: string) {
  return (await apiRequest<{ support_request: SupportRequest }>(`/me/support-requests/${id(requestId)}/undo`, { method: "POST", token }))
    .support_request;
}

export function replyToSupportRequest(token: string, requestId: string, body: { kind: SupportReplyKind; text?: string | null }) {
  return apiRequest<SupportReplyResponse>(`/me/support-requests/${id(requestId)}/replies`, { method: "POST", token, body });
}

export async function fetchWellnessSummarySharing(token: string) {
  return (await apiRequest<{ sharing: WellnessSummarySharing }>("/me/wellness-summary-sharing", { token })).sharing;
}

export async function updateWellnessSummarySharing(token: string, body: WellnessSummarySharingRequest) {
  return (await apiRequest<{ sharing: WellnessSummarySharing }>("/me/wellness-summary-sharing", { method: "PUT", token, body })).sharing;
}

export async function fetchWellnessAccessLog(token: string) {
  const data = await apiRequest<{ entries?: WellnessAccessLogEntry[] }>("/me/wellness-summary-sharing/access-log", { token });
  return data.entries ?? [];
}

/** The coach's read of a client's weekly summary; `shared: false` without the member's grant (logged either way). */
export function fetchClientWellnessSummary(token: string, clientUserId: string, week?: string | null) {
  return apiRequest<ClientWellnessSummary>(`/staff/clients/${id(clientUserId)}/wellness-summary${week ? `?week=${week}` : ""}`, { token });
}
