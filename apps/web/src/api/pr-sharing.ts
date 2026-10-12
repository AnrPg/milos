import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

// ADR-129: personal PR sharing - coach-visibility opt-out, explicit read-only
// grants to other accounts, and the grantee's "Shared with me" view.

export type PRSharingSettings =
  paths["/api/pr-sharing"]["get"]["responses"]["200"]["content"]["application/json"];

export type PRShareGrant = PRSharingSettings["grants"][number];

export type PRsSharedWithMe =
  paths["/api/pr-sharing/shared-with-me"]["get"]["responses"]["200"]["content"]["application/json"];

export type SharedPRCollection = PRsSharedWithMe["shared"][number];

export type SharedPR = SharedPRCollection["prs"][number];

type CoachVisibilityRequest = NonNullable<
  paths["/api/pr-sharing/coach-visibility"]["put"]["requestBody"]
>["content"]["application/json"];

type GrantRequest = NonNullable<
  paths["/api/pr-sharing/grants"]["post"]["requestBody"]
>["content"]["application/json"];

export function fetchPRSharing(token: string) {
  return apiRequest<PRSharingSettings>("/pr-sharing", { token });
}

export function updatePRCoachVisibility(token: string, coachVisibility: boolean) {
  const body: CoachVisibilityRequest = { coach_visibility: coachVisibility };
  return apiRequest<PRSharingSettings>("/pr-sharing/coach-visibility", {
    method: "PUT",
    token,
    body,
  });
}

export function grantPRAccess(token: string, granteeUserId: string) {
  const body: GrantRequest = { grantee_user_id: granteeUserId };
  return apiRequest<PRShareGrant>("/pr-sharing/grants", { method: "POST", token, body });
}

export function revokePRAccess(token: string, grantId: string) {
  return apiRequest<void>(`/pr-sharing/grants/${grantId}`, { method: "DELETE", token });
}

export function fetchPRsSharedWithMe(token: string) {
  return apiRequest<PRsSharedWithMe>("/pr-sharing/shared-with-me", { token });
}
