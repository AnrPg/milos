import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

/** ADR-207: the login's pending email change (null when none) and any lock. */
export type EmailChangeStatus =
  paths["/api/me/email-change"]["get"]["responses"]["200"]["content"]["application/json"];
export type EmailChangeConfirmed =
  paths["/api/auth/email-change/confirm"]["post"]["responses"]["200"]["content"]["application/json"];
export type EmailChangeReverted =
  paths["/api/auth/email-change/revert"]["post"]["responses"]["200"]["content"]["application/json"];

export function fetchEmailChange(token: string) {
  return apiRequest<EmailChangeStatus>("/me/email-change", { token, scope: "account" });
}

/** Mails a link to the new address; the email changes only once it is opened. */
export function requestEmailChange(token: string, email: string, currentPassword: string) {
  return apiRequest<EmailChangeStatus>("/me/email-change", {
    method: "POST",
    token,
    body: { email, current_password: currentPassword },
    scope: "account",
  });
}

export function resendEmailChange(token: string) {
  return apiRequest<EmailChangeStatus>("/me/email-change/resend", { method: "POST", token, scope: "account" });
}

export function cancelEmailChange(token: string) {
  return apiRequest<EmailChangeStatus>("/me/email-change", { method: "DELETE", token, scope: "account" });
}

/** The link sent to the new address. A browser signed in to the same account gets a fresh session. */
export function confirmEmailChange(linkToken: string) {
  return apiRequest<EmailChangeConfirmed>("/auth/email-change/confirm", {
    method: "POST",
    body: { token: linkToken },
  });
}

/** "This wasn't me", from the old address. */
export function revertEmailChange(linkToken: string) {
  return apiRequest<EmailChangeReverted>("/auth/email-change/revert", {
    method: "POST",
    body: { token: linkToken },
  });
}
