import type { components } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

// ADR-111 tenant logo upload. Tenant owners/admins use the `/admin/branding`
// routes (scoped to the selected organization by the API client); vendors use
// the platform routes for any organization.

export type OrganizationBranding = components["schemas"]["OrganizationBranding"];
export type OrganizationLogoUpload = components["schemas"]["OrganizationLogoUpload"];
export type OrganizationLogoContentType =
  components["schemas"]["OrganizationLogoUploadRequest"]["content_type"];

type BrandingResponse = components["schemas"]["OrganizationBrandingResponse"];

export type OrganizationLogoApi = {
  requestUpload: (file: { type: string; size: number }) => Promise<OrganizationLogoUpload>;
  finalize: (key: string) => Promise<OrganizationBranding>;
  remove: () => Promise<OrganizationBranding>;
};

export async function fetchAdminBranding(token: string) {
  const result = await apiRequest<BrandingResponse>("/admin/branding", { token });
  return result.branding;
}

export function adminLogoApi(token: string): OrganizationLogoApi {
  return logoApi(token, "/admin/branding/logo");
}

export function platformLogoApi(token: string, organizationId: string): OrganizationLogoApi {
  return logoApi(token, `/platform/organizations/${organizationId}/branding/logo`);
}

function logoApi(token: string, base: string): OrganizationLogoApi {
  return {
    requestUpload: (file) =>
      apiRequest<OrganizationLogoUpload>(`${base}/upload-url`, {
        method: "POST",
        token,
        body: { content_type: file.type, byte_size: file.size },
      }),
    finalize: async (key) =>
      (
        await apiRequest<BrandingResponse>(base, {
          method: "PUT",
          token,
          body: { logo_key: key },
        })
      ).branding,
    remove: async () =>
      (await apiRequest<BrandingResponse>(base, { method: "DELETE", token })).branding,
  };
}
