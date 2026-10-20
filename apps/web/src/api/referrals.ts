import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Member referrals (ADR-156, P2-M8, board 11). A member's «Φέρε φίλο» at one
 * box (`/org/:slug/me/referrals`), the public invite page behind
 * `/r/<code>`, the claim a friend makes once signed in, and staff's
 * «Οικονομικά › Συστάσεις» queue through the selected gym (`/admin`).
 */
export type ReferralOverview = components["schemas"]["ReferralOverview"];
export type ReferralProgramTerms = NonNullable<ReferralOverview["program"]>;
export type ReferralGift = NonNullable<ReferralProgramTerms["gift"]>;
export type ReferralInvite = components["schemas"]["ReferralInvite"];
export type ReferralStage = ReferralInvite["stage"];
export type ReferralRewardStatus = NonNullable<ReferralInvite["reward"]>["status"];
export type ReferralEvent = ReferralOverview["events"][number];
export type ReferralInvitePage = components["schemas"]["ReferralInvitePage"]["invite"];
export type ReferralClaim = components["schemas"]["ReferralClaim"];
export type ReferralChannel = NonNullable<ReferralClaim["channel"]>;
export type ReferralClaimResult = components["schemas"]["ReferralClaimResult"];
export type ReferralClaimOutcome = ReferralClaimResult["outcome"];
export type StaffReferralInvite = components["schemas"]["ReferralInviteForStaff"];
export type StaffReferralStatus = StaffReferralInvite["status"];
export type StaffReferralList = components["schemas"]["ReferralStaffList"];
export type StaffReferralFilter = "all" | "review";

export const REFERRALS_KEY = ["referrals"] as const;
export const myReferralsKey = (slug: string) => ["referrals", "mine", slug] as const;
export const referralInviteKey = (code: string) => ["referrals", "invite", code] as const;
export const STAFF_REFERRALS_KEY = ["admin", "referrals"] as const;
export const staffReferralsKey = (filter: StaffReferralFilter) => ["admin", "referrals", filter] as const;

const enc = (value: string) => encodeURIComponent(value);

// Member ----------------------------------------------------------------------

export function fetchMyReferrals(token: string, slug: string) {
  return apiRequest<ReferralOverview>(`/org/${enc(slug)}/me/referrals`, { token });
}

/** «Νέος σύνδεσμος»: the old link stops working, invites made with it stay. */
export function rotateReferralCode(token: string, slug: string) {
  return apiRequest<{ code: string; path: string }>(`/org/${enc(slug)}/me/referrals/code`, {
    method: "POST",
    token,
  });
}

// Friend ----------------------------------------------------------------------

export async function fetchReferralInvite(code: string) {
  const data = await apiRequest<{ invite: ReferralInvitePage }>(`/public/referrals/${enc(code)}`);
  return data.invite;
}

export function claimReferral(token: string, claim: ReferralClaim) {
  return apiRequest<ReferralClaimResult>("/referrals/claim", { method: "POST", token, body: claim });
}

// Staff -----------------------------------------------------------------------

const BASE = "/admin/referrals";

export function fetchStaffReferrals(token: string, filter: StaffReferralFilter) {
  return apiRequest<StaffReferralList>(filter === "review" ? `${BASE}?filter=review` : BASE, { token });
}

type StaffInviteResponse = { invite: StaffReferralInvite };

export async function approveReferral(token: string, id: string) {
  const data = await apiRequest<StaffInviteResponse>(`${BASE}/${enc(id)}/approve`, { method: "POST", token });
  return data.invite;
}

export async function rejectReferral(token: string, id: string, note: string | null) {
  const data = await apiRequest<StaffInviteResponse>(`${BASE}/${enc(id)}/reject`, {
    method: "POST",
    token,
    body: { note },
  });
  return data.invite;
}

export async function markReferralGiven(token: string, id: string) {
  const data = await apiRequest<StaffInviteResponse>(`${BASE}/${enc(id)}/given`, { method: "POST", token });
  return data.invite;
}

export async function reassignReferral(token: string, id: string, referrerUserId: string, note: string | null) {
  const data = await apiRequest<StaffInviteResponse>(`${BASE}/${enc(id)}/referrer`, {
    method: "PUT",
    token,
    body: { referrer_user_id: referrerUserId, note },
  });
  return data.invite;
}

export async function applyFriendGift(token: string, id: string) {
  const data = await apiRequest<StaffInviteResponse>(`${BASE}/${enc(id)}/friend-gift`, { method: "POST", token });
  return data.invite;
}
