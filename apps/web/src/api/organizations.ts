import type { paths } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

export type OrganizationMembership =
  paths["/api/memberships"]["get"]["responses"]["200"]["content"]["application/json"][number];

export function fetchOrganizationMemberships(token: string) {
  return apiRequest<OrganizationMembership[]>("/memberships", { token });
}

type OrgPaths = paths;

export type IssuedInvitation =
  OrgPaths["/api/org/{organization_slug}/invitations"]["post"]["responses"]["201"]["content"]["application/json"];
export type PendingInvitation =
  OrgPaths["/api/org/{organization_slug}/invitations"]["get"]["responses"]["200"]["content"]["application/json"][number];
export type JoinLinkSettings =
  OrgPaths["/api/org/{organization_slug}/join-link"]["get"]["responses"]["200"]["content"]["application/json"];
export type PublicJoinLink =
  OrgPaths["/api/auth/join/{slug}"]["get"]["responses"]["200"]["content"]["application/json"];
export type ClientRole = "member" | "athlete";

const orgPath = (slug: string, path: string) => `/org/${encodeURIComponent(slug)}${path}`;

export function issueClientInvitation(
  token: string,
  slug: string,
  body: {
    role: string;
    lifetime_seconds: number;
    intended_email?: string;
    /** ADR-186: several roles and the branches of a staff invitation. */
    roles?: string[];
    all_locations?: boolean;
    location_ids?: string[];
    /** ADR-209: email the invitation to `intended_email` (its token stays in the email). */
    send_email?: boolean;
    email_locale?: string;
  },
) {
  return apiRequest<IssuedInvitation>(orgPath(slug, "/invitations"), { method: "POST", token, body });
}

export type BulkInvitationResult = {
  results: { email: string; status?: "queued"; invitation_id?: string; error?: string }[];
  sent: number;
  failed: number;
  skipped: string[];
};

/** ADR-209: the most addresses one bulk request takes. */
export const BULK_INVITE_MAX = 200;

/** ADR-209: one invitation and email per address (`POST /invitations/bulk`). */
export function bulkInvite(
  token: string,
  slug: string,
  body: {
    emails: string[];
    role: string;
    lifetime_seconds: number;
    email_locale?: string;
    roles?: string[];
    all_locations?: boolean;
    location_ids?: string[];
  },
) {
  return apiRequest<BulkInvitationResult>(orgPath(slug, "/invitations/bulk"), { method: "POST", token, body });
}

/** ADR-209: re-issues an emailed invitation and emails the new link; the old one stops working. */
export function resendInvitation(token: string, slug: string, id: string) {
  return apiRequest<PendingInvitation>(orgPath(slug, `/invitations/${encodeURIComponent(id)}/resend`), {
    method: "POST",
    token,
  });
}

/**
 * ADR-209: the addresses in pasted text or a CSV file: split on commas,
 * semicolons, quotes and whitespace, lower-cased, without repeats. Values that
 * are not shaped like an address are returned separately.
 */
export function parseInviteAddresses(text: string): { emails: string[]; skipped: string[] } {
  const seen = new Set<string>();
  const emails: string[] = [];
  const skipped: string[] = [];
  for (const raw of text.split(/[\s,;"']+/u)) {
    const value = raw.trim().toLowerCase();
    if (!value || seen.has(value)) continue;
    seen.add(value);
    if (/^[^@\s<>()]+@[^@\s<>()]+\.[^@\s<>()]+$/u.test(value)) emails.push(value);
    else skipped.push(value);
  }
  return { emails, skipped };
}

export function listPendingInvitations(token: string, slug: string) {
  return apiRequest<PendingInvitation[]>(orgPath(slug, "/invitations"), { token });
}

export function revokeInvitation(token: string, slug: string, id: string) {
  return apiRequest<void>(orgPath(slug, `/invitations/${id}`), { method: "DELETE", token });
}

export function fetchJoinLink(token: string, slug: string) {
  return apiRequest<JoinLinkSettings>(orgPath(slug, "/join-link"), { token });
}

/** ADR-216: turn one join link on or off, or give the athlete link a new key. */
export type JoinLinkChange = { role: ClientRole; enabled?: boolean; rotate_key?: boolean };

export function updateJoinLink(token: string, slug: string, body: JoinLinkChange) {
  return apiRequest<JoinLinkSettings>(orgPath(slug, "/join-link"), { method: "PUT", token, body });
}

/**
 * ADR-216: a box has one join link per client role. The member link is the box
 * address; the athlete link adds a secret key, so the visitor never picks a role.
 */
export type JoinLinkTarget = { slug: string; athleteKey?: string | null };

export function joinPath({ slug, athleteKey }: JoinLinkTarget) {
  const base = `/join/${encodeURIComponent(slug)}`;
  return athleteKey ? `${base}/athlete/${encodeURIComponent(athleteKey)}` : base;
}

export function inspectJoinLink(link: JoinLinkTarget) {
  return apiRequest<PublicJoinLink>(`/auth${joinPath(link)}`);
}

export function joinOrganization(token: string, link: JoinLinkTarget) {
  return apiRequest<OrganizationMembership>(`/memberships${joinPath(link)}`, {
    method: "POST",
    token,
  });
}

export function invitationUrl(origin: string, invitation: { role: string; roles?: string[] | null; token?: string | null }) {
  return `${origin}${invitationSignUpPath(invitation)}?token=${encodeURIComponent(invitation.token ?? "")}`;
}

/** The sign-up page of an invitation: owners and admins register on `/set-admin`. */
export function invitationSignUpPath(invitation: { role: string; roles?: string[] | null }) {
  const roles = invitation.roles?.length ? invitation.roles : [invitation.role];
  return roles.includes("owner") || roles.includes("admin") ? "/set-admin" : "/register";
}

/**
 * ADR-209: the invitation token of the current page: `#token=` (emailed
 * links keep it in the fragment, away from server logs) or `?token=`.
 */
export function invitationTokenFromLocation(location: { hash: string; search: string }): string {
  const fromHash = new URLSearchParams(location.hash.replace(/^#/, "")).get("token");
  const fromQuery = new URLSearchParams(location.search).get("token");
  return (fromHash ?? fromQuery ?? "").trim();
}

export function joinUrl(origin: string, link: JoinLinkTarget) {
  return `${origin}${joinPath(link)}`;
}

/** An existing account accepts an invitation code (`POST /memberships/redeem`). */
export function redeemInvitation(token: string, invitationToken: string) {
  return apiRequest<OrganizationMembership>("/memberships/redeem", {
    method: "POST",
    token,
    body: { invitation_token: invitationToken },
  });
}
