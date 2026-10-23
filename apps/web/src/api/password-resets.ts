import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/**
 * ADR-187: the handler side of password recovery. The vendor, the boxes'
 * owner/admin/front desk and the person's coach see the requests they can
 * handle, claim one, check it is really the person off-app and mail them a
 * one-time reset link from their own mailbox.
 */
type Json<Op extends keyof operations> = operations[Op] extends {
  responses: { 200: { content: { "application/json": infer Body } } };
}
  ? Body
  : never;

export type PasswordResetInbox = Json<"PaleeWeb.PasswordRecoveryController.inbox">;
export type PasswordResetRequest = PasswordResetInbox["requests"][number];
export type PasswordResetState = PasswordResetRequest["state"];
export type PasswordResetLink = Json<"PaleeWeb.PasswordRecoveryController.issue_link">;
export type PasswordResetLogEntry = Json<"PaleeWeb.PasswordRecoveryController.log">["entries"][number];

export const PASSWORD_RESETS_KEY = ["password-resets"] as const;
export const PASSWORD_RESET_LOG_KEY = ["platform", "password-reset-log"] as const;

const path = (id: string, action: string) => `/password-resets/${encodeURIComponent(id)}/${action}`;

export function fetchPasswordResets(token: string) {
  return apiRequest<PasswordResetInbox>("/password-resets", { token, scope: "account" });
}

export function claimPasswordReset(token: string, id: string) {
  return apiRequest<{ request: PasswordResetRequest }>(path(id, "claim"), { method: "POST", token, scope: "account" });
}

export function releasePasswordReset(token: string, id: string) {
  return apiRequest<{ request: PasswordResetRequest }>(path(id, "release"), { method: "POST", token, scope: "account" });
}

export function issuePasswordResetLink(token: string, id: string) {
  return apiRequest<PasswordResetLink>(path(id, "link"), { method: "POST", token, scope: "account" });
}

export function rejectPasswordReset(token: string, id: string) {
  return apiRequest<void>(path(id, "reject"), { method: "POST", token, scope: "account" });
}

export function dismissPasswordReset(token: string, id: string) {
  return apiRequest<void>(path(id, "dismiss"), { method: "POST", token, scope: "account" });
}

export function hidePasswordReset(token: string, id: string) {
  return apiRequest<void>(path(id, "hide"), { method: "POST", token, scope: "account" });
}

export function fetchPasswordResetLog(token: string) {
  return apiRequest<{ entries: PasswordResetLogEntry[] }>("/platform/password-reset-log", { token, scope: "account" });
}
