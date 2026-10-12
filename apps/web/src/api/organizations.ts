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
  body: { role: ClientRole; lifetime_seconds: number; intended_email?: string },
) {
  return apiRequest<IssuedInvitation>(orgPath(slug, "/invitations"), { method: "POST", token, body });
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

export function updateJoinLink(token: string, slug: string, body: Partial<JoinLinkSettings>) {
  return apiRequest<JoinLinkSettings>(orgPath(slug, "/join-link"), { method: "PUT", token, body });
}

export function inspectJoinLink(slug: string) {
  return apiRequest<PublicJoinLink>(`/auth/join/${encodeURIComponent(slug)}`);
}

export function joinOrganization(token: string, slug: string) {
  return apiRequest<OrganizationMembership>(`/memberships/join/${encodeURIComponent(slug)}`, {
    method: "POST",
    token,
  });
}

export function invitationUrl(origin: string, invitation: { role: string; token?: string | null }) {
  const route = invitation.role === "owner" || invitation.role === "admin" ? "/set-admin" : "/register";
  return `${origin}${route}?token=${encodeURIComponent(invitation.token ?? "")}`;
}

export function joinUrl(origin: string, slug: string) {
  return `${origin}/join/${encodeURIComponent(slug)}`;
}
