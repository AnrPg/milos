import { ApiError } from "@/api/client";

/** API error codes of ADR-155 that have their own wording in the CheckIn namespace. */
const CODES = [
  "invalid_door_code",
  "invalid_scan_token",
  "booking_not_in_window",
  "undo_expired",
  "invalid_undo_token",
  "invalid_member_code",
  "not_a_member",
  "invalid_pass",
  "pass_revoked",
  "override_not_allowed",
  "check_in_problems",
  "wallet_not_configured",
  "wallet_pass_conflict",
  "wallet_requires_static_code",
  "member_code_not_static",
  "member_code_revoked",
] as const;

export type CheckInErrorCode = (typeof CODES)[number];

/** The message key for an error: its own wording, «offline», or a generic line. */
export function checkInErrorKey(error: unknown): string {
  if (error instanceof ApiError) {
    const code = error.payload.code;
    if (code && (CODES as readonly string[]).includes(code)) return ["error", code].join("_");
    if (error.status === 403) return "error_forbidden";
    if (error.status === 404) return "error_not_found";
    return "errorGeneric";
  }
  if (error instanceof TypeError) return "errorOffline";
  return "errorGeneric";
}

export function errorCode(error: unknown) {
  return error instanceof ApiError ? (error.payload.code ?? null) : null;
}
