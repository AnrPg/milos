import { apiRequest } from "@/api/client";
import type { AuthTokens, CurrentUser } from "@/api/auth";
import type { paths } from "@/api/generated/schema";

/** ADR-187: the up to three profiles of the signed-in login. */
export type AccountProfiles =
  paths["/api/auth/profiles"]["get"]["responses"]["200"]["content"]["application/json"];
export type AccountProfile = AccountProfiles["profiles"][number];
export type NewProfile = NonNullable<
  paths["/api/auth/profiles"]["post"]["requestBody"]
>["content"]["application/json"];
export type RecoveryCodesStatus =
  paths["/api/auth/recovery-codes"]["get"]["responses"]["200"]["content"]["application/json"];

export function fetchAccountProfiles(token: string) {
  return apiRequest<AccountProfiles>("/auth/profiles", { token, scope: "account" });
}

/** Adds a profile to the login (at most `profile_limit`); answers the new list. */
export function addAccountProfile(token: string, payload: NewProfile) {
  return apiRequest<AccountProfiles>("/auth/profiles", {
    method: "POST",
    token,
    body: payload,
    scope: "account",
  });
}

/** A new session (access token + refresh cookie) for another profile of the same login. */
export function switchAccountProfile(token: string, userId: string) {
  return apiRequest<AuthTokens & { user: CurrentUser }>("/auth/switch-profile", {
    method: "POST",
    token,
    body: { user_id: userId },
    scope: "account",
  });
}

export function fetchRecoveryCodesStatus(token: string) {
  return apiRequest<RecoveryCodesStatus>("/auth/recovery-codes", { token, scope: "account" });
}

/** Ten new one-time codes; the old ones stop working. Needs the current password. */
export function generateRecoveryCodes(token: string, currentPassword: string) {
  return apiRequest<{ codes: string[] }>("/auth/recovery-codes", {
    method: "POST",
    token,
    body: { current_password: currentPassword },
    scope: "account",
  });
}
