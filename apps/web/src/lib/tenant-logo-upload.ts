import type { OrganizationBranding, OrganizationLogoApi } from "@/api/organization-branding";

// ADR-121: client-side mirror of the server's logo policy. The server
// re-validates the stored bytes (magic bytes + size), so these checks only
// spare the user a pointless upload. SVG is deliberately not accepted.
export const TENANT_LOGO_CONTENT_TYPES = ["image/png", "image/jpeg", "image/webp"] as const;
export const TENANT_LOGO_MAX_BYTES = 2 * 1024 * 1024;
export const TENANT_LOGO_ACCEPT = TENANT_LOGO_CONTENT_TYPES.join(",");

export type TenantLogoFileProblem = "empty" | "unsupportedType" | "tooLarge";

export function validateTenantLogoFile(file: { type: string; size: number }): TenantLogoFileProblem | null {
  if (!(TENANT_LOGO_CONTENT_TYPES as readonly string[]).includes(file.type)) return "unsupportedType";
  if (file.size <= 0) return "empty";
  if (file.size > TENANT_LOGO_MAX_BYTES) return "tooLarge";
  return null;
}

export class TenantLogoUploadError extends Error {
  constructor(public readonly reason: TenantLogoFileProblem | "storageRejected") {
    super(reason);
    this.name = "TenantLogoUploadError";
  }
}

type PutObject = (url: string, init: { method: "PUT"; body: Blob; headers: Record<string, string> }) => Promise<{ ok: boolean }>;

/**
 * Request a presigned upload, PUT the file straight to object storage, then
 * ask the API to verify and adopt it. Rejects with `TenantLogoUploadError` for
 * client-side problems or a failed storage PUT; API errors propagate as-is.
 */
export async function uploadTenantLogo(
  file: File,
  api: Pick<OrganizationLogoApi, "requestUpload" | "finalize">,
  putObject: PutObject = (url, init) => fetch(url, init),
): Promise<OrganizationBranding> {
  const problem = validateTenantLogoFile(file);
  if (problem) throw new TenantLogoUploadError(problem);

  const upload = await api.requestUpload(file);
  const response = await putObject(upload.upload_url, {
    method: "PUT",
    body: file,
    headers: upload.required_headers,
  });
  if (!response.ok) throw new TenantLogoUploadError("storageRejected");

  return api.finalize(upload.key);
}
