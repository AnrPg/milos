import { ApiError, apiRequest } from "@/api/client";

/** ADR-213: what a resend answers when it went out, or had nothing to do. */
export type VerificationEmailResult = { status: "sent" | "already_verified" };

/**
 * ADR-213: emails the signed-in login a new verification link. A throttled
 * request throws an ApiError 429 whose payload carries `retry_after_seconds`
 * (read it with `verificationRetryAfter`).
 */
export function resendVerificationEmail(token: string) {
  return apiRequest<VerificationEmailResult>("/auth/verification-email", {
    method: "POST",
    token,
    scope: "account",
  });
}

/** ADR-213: spends the emailed link's token; the page reads it from the URL fragment. */
export function verifyEmailToken(token: string) {
  return apiRequest<{ email_verified: boolean }>(
    "/auth/verify-email",
    { method: "POST", body: { token }, scope: "account" },
    false,
  );
}

/** Seconds to wait when a resend was throttled (429), else null. */
export function verificationRetryAfter(error: unknown): number | null {
  if (!(error instanceof ApiError) || error.status !== 429) return null;
  const seconds = (error.payload as Record<string, unknown>).retry_after_seconds;
  return typeof seconds === "number" && Number.isFinite(seconds) && seconds > 0 ? Math.ceil(seconds) : 60;
}

export type VerifyLinkFailure = "invalid" | "used" | "expired" | "email_changed" | "other";

/** What a failed POST /auth/verify-email means for the page. */
export function verifyLinkFailure(error: unknown): VerifyLinkFailure {
  if (!(error instanceof ApiError)) return "other";
  switch (error.payload.code) {
    case "invalid_verification_link":
      return "invalid";
    case "used_verification_link":
      return "used";
    case "expired_verification_link":
      return "expired";
    case "verification_email_changed":
      return "email_changed";
    default:
      return error.status === 410 ? "expired" : "other";
  }
}
