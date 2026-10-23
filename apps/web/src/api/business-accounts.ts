import { ApiError, BUSINESS_NOT_ACTIVATED_CODE, apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * ADR-184: business accounts. The business step of sign-up, requests to the
 * Palee team (Εγώ › Ρυθμίσεις), the demo data of a business in demo mode,
 * the activation link and the vendors' queue.
 */
export type BusinessOrganization = components["schemas"]["BusinessOrganization"];
export type BusinessDemoStatus = components["schemas"]["BusinessDemoStatus"];
export type BusinessRequest = components["schemas"]["BusinessRequest"];
export type BusinessActivationLink = components["schemas"]["BusinessActivationLink"];
export type BusinessAccountsQueue = components["schemas"]["BusinessAccountsQueue"];
export type BusinessRequestDecision = components["schemas"]["BusinessRequestDecision"];
export type BusinessActivationPreview = components["schemas"]["BusinessActivationPreview"];
export type BusinessActivationResult = components["schemas"]["BusinessActivationResult"];
export type BusinessArchivedDemos = components["schemas"]["BusinessArchivedDemos"];
export type BusinessArchivedDemo = BusinessArchivedDemos["businesses"][number];
export type BusinessReopenedDemo = components["schemas"]["BusinessReopenedDemo"];
export type BusinessKind = BusinessRequest["business_kind"];
export type ActivationRole = BusinessActivationLink["role"];
export type DemoSection = "members" | "schedule" | "finance" | "workouts";

export type BusinessDetails = {
  business_kind: BusinessKind;
  business_name: string;
  city?: string | null;
  phone?: string | null;
  message?: string | null;
};

export const BUSINESS_KINDS: BusinessKind[] = ["gym", "coach"];
export const DEMO_SECTIONS: DemoSection[] = ["members", "schedule", "finance", "workouts"];
export const ADMIN_BUSINESS_KEY = ["admin", "business"] as const;
export const MY_BUSINESS_REQUESTS_KEY = ["me", "business-requests"] as const;
export const MY_ARCHIVED_DEMOS_KEY = ["me", "archived-demos"] as const;
export const PLATFORM_BUSINESS_KEY = ["platform", "business-accounts"] as const;

export function isBusinessNotActivated(error: unknown) {
  return error instanceof ApiError && error.payload.code === BUSINESS_NOT_ACTIVATED_CODE;
}

/**
 * The screen's demo section: what the floating button fills on this admin
 * page. Anything without its own section fills everything.
 */
export function demoSectionForPath(pathname: string): DemoSection | "all" {
  const path = pathname.replace(/^\/org\/[^/]+/, "");
  if (/^\/admin\/users(\/|$)/.test(path)) return "members";
  if (/^\/admin\/(schedule|class-schedule)(\/|$)/.test(path)) return "schedule";
  if (/^\/admin\/finance(\/|$)/.test(path)) return "finance";
  if (/^\/admin\/workouts(\/|$)/.test(path)) return "workouts";
  return "all";
}

export function isAdminPath(pathname: string) {
  return /^(\/org\/[^/]+)?\/admin(\/|$)/.test(pathname);
}

export function signUpBusiness(
  token: string,
  body: BusinessDetails & { timezone?: string | null; default_locale?: string | null },
) {
  return apiRequest<BusinessOrganization>("/business-accounts", { method: "POST", token, scope: "account", body });
}

export function fetchMyBusinessRequests(token: string) {
  return apiRequest<{ requests: BusinessRequest[] }>("/me/business-requests", { token, scope: "account" });
}

export function requestConversion(token: string, body: BusinessDetails) {
  return apiRequest<BusinessRequest>("/me/business-requests", { method: "POST", token, scope: "account", body });
}

export function cancelBusinessRequest(token: string, id: string) {
  return apiRequest<BusinessRequest>(`/me/business-requests/${encodeURIComponent(id)}/cancel`, {
    method: "POST",
    token,
    scope: "account",
  });
}

/** ADR-184 follow-up: the person's demo businesses archived for inactivity. */
export function fetchArchivedDemos(token: string) {
  return apiRequest<BusinessArchivedDemos>("/me/archived-demos", { token, scope: "account" });
}

/** Reopens an archived demo: empty, in demo mode, with a new activation request. */
export function reopenArchivedDemo(token: string, id: string) {
  return apiRequest<BusinessReopenedDemo>(`/me/archived-demos/${encodeURIComponent(id)}/reopen`, {
    method: "POST",
    token,
    scope: "account",
  });
}

export function inspectActivation(token: string, activationToken: string) {
  return apiRequest<BusinessActivationPreview>("/business-activation/inspect", {
    method: "POST",
    token,
    scope: "account",
    body: { token: activationToken },
  });
}

export function redeemActivation(token: string, activationToken: string) {
  return apiRequest<BusinessActivationResult>("/business-activation/redeem", {
    method: "POST",
    token,
    scope: "account",
    body: { token: activationToken },
  });
}

export function fetchBusinessStatus(token: string) {
  return apiRequest<BusinessDemoStatus>("/admin/business", { token });
}

export function seedDemoData(token: string, section: DemoSection | "all") {
  return apiRequest<BusinessDemoStatus>("/admin/business/demo-data", { method: "POST", token, body: { section } });
}

export function removeDemoData(token: string) {
  return apiRequest<BusinessDemoStatus>("/admin/business/demo-data", { method: "DELETE", token });
}

export function requestActivation(token: string, body: { phone?: string | null; message?: string | null } = {}) {
  return apiRequest<BusinessRequest>("/admin/business/activation-request", { method: "POST", token, body });
}

export function fetchBusinessQueue(token: string) {
  return apiRequest<BusinessAccountsQueue>("/platform/business-accounts", { token, scope: "account" });
}

export function decideBusinessRequest(
  token: string,
  id: string,
  body: { decision: "approve" | "decline"; note?: string | null; role?: ActivationRole },
) {
  return apiRequest<BusinessRequestDecision>(`/platform/business-requests/${encodeURIComponent(id)}/decision`, {
    method: "POST",
    token,
    scope: "account",
    body,
  });
}

export function issueActivationLink(
  token: string,
  organizationId: string,
  body: { role: ActivationRole; user_id?: string | null; nickname?: string | null },
) {
  return apiRequest<BusinessActivationLink>(
    `/platform/organizations/${encodeURIComponent(organizationId)}/activation-links`,
    { method: "POST", token, scope: "account", body },
  );
}

export function revokeActivationLink(token: string, id: string) {
  return apiRequest<BusinessActivationLink>(`/platform/activation-links/${encodeURIComponent(id)}`, {
    method: "DELETE",
    token,
    scope: "account",
  });
}

/** The absolute activation URL a vendor copies and sends. */
export function activationUrl(path: string | null | undefined) {
  if (!path) return "";
  if (typeof window === "undefined") return path;
  return `${window.location.origin}${path}`;
}
