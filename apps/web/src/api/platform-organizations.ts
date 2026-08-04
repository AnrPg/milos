import { apiRequest } from "@/api/client";

export type OrganizationStatus = "active" | "suspended" | "archived";

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
};

export type OrganizationSettings = {
  organization_id: string;
  timezone: string;
  default_locale: string;
  invitation_lifetime_seconds: number;
  brand_name: string | null;
  brand_logo_url: string | null;
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
    role: "owner";
  };
  canonical_path: string;
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
