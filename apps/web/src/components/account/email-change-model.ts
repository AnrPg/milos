import { ApiError } from "@/api/client";

/** A key under the `emailChange` namespace plus its values. */
export type EmailChangeMessage = { key: string; values?: Record<string, string | number | Date> };

/** What the Settings form shows for a refused request, resend or cancel; null for anything else. */
export function describeEmailChangeError(error: unknown): EmailChangeMessage | null {
  if (!(error instanceof ApiError)) return null;
  const payload = error.payload as Record<string, unknown>;

  switch (payload.code) {
    case "invalid_current_password":
      return { key: "errors.currentPassword" };
    case "invalid_email":
    case "invalid_address":
      return { key: "errors.invalidEmail" };
    case "email_unchanged":
      return { key: "errors.unchanged" };
    case "suppressed":
      return { key: "errors.suppressed" };
    case "throttled":
      return { key: "errors.throttled" };
    case "no_pending_email_change":
      return { key: "errors.nothingPending" };
    case "email_change_locked": {
      const until = typeof payload.locked_until === "string" ? new Date(payload.locked_until) : null;
      return until && !Number.isNaN(until.getTime())
        ? { key: "errors.lockedUntil", values: { date: until } }
        : { key: "errors.locked" };
    }
  }
  if (error.status === 429) return { key: "errors.throttled" };
  return null;
}

export type EmailChangeLinkFailure = "invalid" | "expired" | "unavailable" | "other";

/** The confirm and revert pages tell an expired link (410) from an unknown or used one, and a taken address (409). */
export function emailChangeLinkFailure(error: unknown): EmailChangeLinkFailure {
  if (!(error instanceof ApiError)) return "other";
  const code = error.payload.code;
  if (error.status === 410 || code === "expired_email_change_link") return "expired";
  if (code === "invalid_email_change_link") return "invalid";
  if (error.status === 409 || code === "email_change_unavailable") return "unavailable";
  return "other";
}
