import type { paths } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

export type OrganizationStatus = "active" | "suspended" | "archived";
export type OrganizationMembershipRole = "owner" | "admin" | "coach" | "member" | "athlete";

export type PlatformOrganization = {
  organization: {
    id: string;
    slug: string;
    name: string;
    status: OrganizationStatus;
    inserted_at: string;
    updated_at: string;
  };
  settings: OrganizationSettings | null;
  canonical_path: string;
  pending_registration: boolean;
};

export type OrganizationSettings = {
  organization_id: string;
  timezone: string;
  default_locale: string;
  invitation_lifetime_seconds: number;
  brand_name: string | null;
  brand_logo_url: string | null;
  /** ADR-121: true when brand_logo_url is derived from an uploaded logo. */
  brand_logo_uploaded?: boolean;
  brand_primary_color: string | null;
  settings: Record<string, unknown>;
};

export type ProvisionOrganizationInput = {
  name: string;
  slug?: string;
  timezone: string;
  default_locale: string;
  invitation_lifetime_seconds: number;
  initial_owner_email?: string;
  brand_name?: string;
  brand_logo_url?: string;
  brand_primary_color?: string;
};

export type ProvisionOrganizationResult = {
  organization: PlatformOrganization["organization"];
  settings: OrganizationSettings;
  initial_owner_invitation: {
    token: string;
    expires_at: string;
    role: "admin";
  };
  canonical_path: string;
};

export type PlatformOrganizationMembership = {
  id: string;
  user_id: string;
  role: OrganizationMembershipRole;
  status: string;
  joined_at: string | null;
  inserted_at: string;
  updated_at: string;
  user: null | {
    id: string;
    nickname: string;
    role: string;
    avatar_url: string | null;
  };
};

export type PlatformOrganizationAccess = {
  organization: PlatformOrganization["organization"];
  memberships: PlatformOrganizationMembership[];
};

export type PlatformInvitationResult = {
  invitation: {
    token: string;
    expires_at: string;
    role: OrganizationMembershipRole;
  };
};

export function listPlatformOrganizations(token: string) {
  return apiRequest<{ organizations: PlatformOrganization[] }>("/platform/organizations", {
    token,
  });
}

export function provisionPlatformOrganization(token: string, input: ProvisionOrganizationInput) {
  return apiRequest<ProvisionOrganizationResult>("/platform/organizations", {
    method: "POST",
    token,
    body: input,
  });
}

export function changePlatformOrganizationLifecycle(
  token: string,
  organizationId: string,
  status: OrganizationStatus,
) {
  return apiRequest<{ organization: PlatformOrganization["organization"] }>(
    `/platform/organizations/${organizationId}/lifecycle`,
    { method: "PATCH", token, body: { status } },
  );
}

export function renamePlatformOrganization(token: string, organizationId: string, name: string) {
  return apiRequest<{ organization: PlatformOrganization["organization"] }>(
    `/platform/organizations/${organizationId}/name`,
    { method: "PATCH", token, body: { name } },
  );
}

// ADR-122 slug rename: impact summary, then a typed-confirmation rename that
// keeps the previous slug as a redirecting alias.
export type OrganizationSlugImpact =
  paths["/api/platform/organizations/{id}/slug-impact"]["get"]["responses"]["200"]["content"]["application/json"];

export type OrganizationSlugRenameResult =
  paths["/api/platform/organizations/{id}/slug"]["patch"]["responses"]["200"]["content"]["application/json"];

export function fetchOrganizationSlugImpact(token: string, organizationId: string) {
  return apiRequest<OrganizationSlugImpact>(`/platform/organizations/${organizationId}/slug-impact`, {
    token,
  });
}

export function renamePlatformOrganizationSlug(
  token: string,
  organizationId: string,
  input: { slug: string; confirmation: string },
) {
  return apiRequest<OrganizationSlugRenameResult>(`/platform/organizations/${organizationId}/slug`, {
    method: "PATCH",
    token,
    body: input,
  });
}

export function changePlatformOrganizationSettings(
  token: string,
  organizationId: string,
  settings: Partial<OrganizationSettings>,
) {
  return apiRequest<{ settings: OrganizationSettings }>(
    `/platform/organizations/${organizationId}/settings`,
    { method: "PATCH", token, body: settings },
  );
}

export function fetchPlatformOrganizationAccess(token: string, organizationId: string) {
  return apiRequest<PlatformOrganizationAccess>(`/platform/organizations/${organizationId}/access`, {
    token,
  });
}

export function issuePlatformOrganizationInvitation(
  token: string,
  organizationId: string,
  input: { role: OrganizationMembershipRole; intended_email?: string; lifetime_seconds?: number },
) {
  return apiRequest<PlatformInvitationResult>(`/platform/organizations/${organizationId}/invitations`, {
    method: "POST",
    token,
    body: input,
  });
}

export function sendOwnerInvitationEmail(
  token: string,
  organizationId: string,
  input: { email: string; token: string },
) {
  return apiRequest<void>(`/platform/organizations/${organizationId}/invitations/email`, {
    method: "POST",
    token,
    body: input,
  });
}

export function updatePlatformOrganizationMembershipRole(
  token: string,
  organizationId: string,
  membershipId: string,
  role: OrganizationMembershipRole,
) {
  return apiRequest<{ membership: PlatformOrganizationMembership }>(
    `/platform/organizations/${organizationId}/memberships/${membershipId}/role`,
    { method: "PATCH", token, body: { role } },
  );
}

// ADR-117 reviewed tenant export/purge workflow.
export type OrganizationPurgeStatus =
  | "requested"
  | "exporting"
  | "exported"
  | "approved"
  | "purging"
  | "completed"
  | "failed"
  | "cancelled";

export type RetentionDisposition = "purge" | "retain" | "retain_anonymized";

export type RetentionReviewEntry = {
  context: string;
  disposition: RetentionDisposition;
  retain_years: number | null;
  retained_until: string | null;
  basis: string;
  record_count: number;
  resources: { resource: string; count: number }[];
};

export type OrganizationPurge = {
  id: string;
  organization_id: string;
  organization_slug: string;
  status: OrganizationPurgeStatus;
  failed_stage: "export" | "purge" | null;
  failure_reason: string | null;
  requested_by_user_id: string;
  requested_at: string;
  export_completed_at: string | null;
  export_byte_size: number | null;
  export_sha256: string | null;
  retention_review: RetentionReviewEntry[];
  approved_by_user_id: string | null;
  approval_mode: "second_vendor" | "typed_confirmation" | null;
  approved_at: string | null;
  purge_started_at: string | null;
  steps: Record<string, unknown>;
  completed_at: string | null;
  cancelled_at: string | null;
};

export type OrganizationPurgeStatusResult = {
  purge: OrganizationPurge;
  export_download_url: string | null;
};

const purgePath = (organizationId: string) => `/platform/organizations/${organizationId}/purge`;

export function fetchOrganizationPurge(token: string, organizationId: string) {
  return apiRequest<OrganizationPurgeStatusResult>(purgePath(organizationId), { token });
}

export function requestOrganizationPurge(token: string, organizationId: string) {
  return apiRequest<{ purge: OrganizationPurge }>(purgePath(organizationId), {
    method: "POST",
    token,
  });
}

export function approveOrganizationPurge(token: string, organizationId: string, confirmation: string) {
  return apiRequest<{ purge: OrganizationPurge }>(`${purgePath(organizationId)}/approve`, {
    method: "POST",
    token,
    body: { confirmation },
  });
}

export function cancelOrganizationPurge(token: string, organizationId: string) {
  return apiRequest<{ purge: OrganizationPurge }>(`${purgePath(organizationId)}/cancel`, {
    method: "POST",
    token,
  });
}

export function resumeOrganizationPurge(token: string, organizationId: string) {
  return apiRequest<{ purge: OrganizationPurge }>(`${purgePath(organizationId)}/resume`, {
    method: "POST",
    token,
  });
}
