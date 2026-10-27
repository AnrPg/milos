import { apiRequest } from "@/api/client";
import type { AuthTokens } from "@/api/auth";
import type { paths } from "@/api/generated/schema";

/** ADR-211: the login's open deletion request, as Settings shows it. */
export type AccountDeletion =
  paths["/api/auth/account-deletion"]["get"]["responses"]["200"]["content"]["application/json"];
export type AccountDeletionRequest = NonNullable<
  paths["/api/auth/account-deletion"]["post"]["requestBody"]
>["content"]["application/json"];

export function fetchAccountDeletion(token: string) {
  return apiRequest<AccountDeletion>("/auth/account-deletion", { token, scope: "account" });
}

/**
 * Asks to delete this profile or the whole account. Needs the password; a
 * verified email then gets a confirmation link, otherwise `confirm_email`
 * schedules it at once (and the session ends).
 */
export function requestAccountDeletion(token: string, payload: AccountDeletionRequest) {
  return apiRequest<AccountDeletion>("/auth/account-deletion", {
    method: "POST",
    token,
    body: payload,
    scope: "account",
  });
}

/** Drops the login's request, awaiting its link or scheduled. */
export function cancelAccountDeletion(token: string) {
  return apiRequest<void>("/auth/account-deletion", { method: "DELETE", token, scope: "account" });
}

/** The emailed confirmation link (`/account-deletion/confirm#token=...`). */
export function confirmAccountDeletion(token: string) {
  return apiRequest<AccountDeletion>("/auth/account-deletion/confirm", { method: "POST", body: { token } });
}

/** The undo link of the "scheduled for deletion" email (`/account-deletion/undo#token=...`). */
export function undoAccountDeletion(token: string) {
  return apiRequest<AccountDeletion>("/auth/account-deletion/undo", { method: "POST", body: { token } });
}

/** Undo from the sign-in form: the same credentials cancel the deletion and sign in. */
export function undoAccountDeletionAndSignIn(payload: { identifier: string; password: string }) {
  return apiRequest<AuthTokens>("/auth/account-deletion/undo-sign-in", { method: "POST", body: payload });
}
