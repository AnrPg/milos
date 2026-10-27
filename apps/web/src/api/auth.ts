import type { paths } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

export type RegisterRequest =
  NonNullable<
    paths["/api/auth/register"]["post"]["requestBody"]
  >["content"]["application/json"];
export type LoginRequest =
  NonNullable<
    paths["/api/auth/login"]["post"]["requestBody"]
  >["content"]["application/json"];
export type AdminRegisterRequest =
  NonNullable<
    paths["/api/auth/register-admin"]["post"]["requestBody"]
  >["content"]["application/json"];
export type InvitedRegisterRequest =
  NonNullable<
    paths["/api/auth/register-member"]["post"]["requestBody"]
  >["content"]["application/json"];
export type InvitationInspection =
  paths["/api/auth/invitations/inspect"]["post"]["responses"]["200"]["content"]["application/json"];
export type AuthTokens =
  paths["/api/auth/login"]["post"]["responses"]["200"]["content"]["application/json"];
export type CurrentUser =
  paths["/api/auth/me"]["get"]["responses"]["200"]["content"]["application/json"] & {
    vendor?: boolean;
  };

export function registerUser(payload: RegisterRequest) {
  return apiRequest<AuthTokens>("/auth/register", { method: "POST", body: payload });
}

export function registerAdminUser(payload: AdminRegisterRequest) {
  return apiRequest<AuthTokens>("/auth/register-admin", { method: "POST", body: payload });
}

export function registerInvitedUser(payload: InvitedRegisterRequest) {
  return apiRequest<AuthTokens>("/auth/register-member", { method: "POST", body: payload });
}

export function inspectInvitation(invitation_token: string) {
  return apiRequest<InvitationInspection>("/auth/invitations/inspect", {
    method: "POST",
    body: { invitation_token },
  });
}

export type AcceptedInvitation =
  paths["/api/auth/accept-invitation"]["post"]["responses"]["200"]["content"]["application/json"];

/**
 * ADR-204: the signed-in profile accepts an invitation itself. When that
 * lifts its role, its old sessions end and a new one comes back.
 */
export function acceptInvitation(token: string, invitationToken: string) {
  return apiRequest<AcceptedInvitation>("/auth/accept-invitation", {
    method: "POST",
    token,
    body: { invitation_token: invitationToken },
  });
}

export function loginUser(payload: LoginRequest) {
  return apiRequest<AuthTokens>("/auth/login", { method: "POST", body: payload });
}

export function refreshSession() {
  return apiRequest<AuthTokens | undefined>("/auth/refresh", { method: "POST" }, false);
}

export function logoutSession() {
  return apiRequest<void>("/auth/logout", { method: "POST" }, false);
}

export function signOutAllDevices(token: string) {
  return apiRequest<void>("/auth/sign-out-all", { method: "POST", token }, false);
}

export function fetchCurrentUser(token: string) {
  return apiRequest<CurrentUser>("/auth/me", { token });
}

export type HandleAvailability =
  paths["/api/auth/handle-available"]["get"]["responses"]["200"]["content"]["application/json"];

/** ADR-187: whether a typed @handle is free, its stored (folded) form and free alternatives. */
export function checkHandleAvailable(handle: string, signal?: AbortSignal) {
  return apiRequest<HandleAvailability>(
    `/auth/handle-available?handle=${encodeURIComponent(handle)}`,
    { signal },
  );
}

/** ADR-187: a free Latin @handle suggested from a display name (null when it has no Latin form). */
export function suggestHandle(displayName: string, signal?: AbortSignal) {
  return apiRequest<{ handle: string | null }>(
    `/auth/handle-suggestion?display_name=${encodeURIComponent(displayName)}`,
    { signal },
  );
}

/** Always answered "sent"; never reveals whether the account exists. */
export function requestPasswordReset(identifier: string) {
  return apiRequest<unknown>("/auth/password-reset-requests", {
    method: "POST",
    body: { identifier },
  });
}

/** Sets a new password with a reset link's token; signs every device out. */
export function completePasswordReset(token: string, password: string) {
  return apiRequest<void>("/auth/password-reset", { method: "POST", body: { token, password } });
}

/** Sets a new password with a one-time recovery code. */
export function resetPasswordWithRecoveryCode(payload: {
  identifier: string;
  code: string;
  password: string;
}) {
  return apiRequest<void>("/auth/password-reset/recovery-code", { method: "POST", body: payload });
}
