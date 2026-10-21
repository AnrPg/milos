import { ApiError } from "@/api/client";
import { clientErrorMessage } from "@/components/client/errors";

/** API error codes of Σώμα (ADR-158) that have their own words. */
export const BODY_ERROR_CODES = [
  "invalid_metric",
  "snapshot_empty",
  "invalid_body_visibility",
  "body_notes_too_long",
  "invalid_pose",
  "too_many_body_photos",
  "pose_taken",
  "body_photo_consent_required",
  "invalid_taken_at",
  "share_confirmation_required",
  "share_needs_two_snapshots",
  "share_photo_missing",
  "media_not_ready",
] as const;

type Translate = (key: string) => string;

export function bodyErrorCode(error: unknown): (typeof BODY_ERROR_CODES)[number] | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return (BODY_ERROR_CODES as readonly string[]).includes(error.payload.code) ? (error.payload.code as (typeof BODY_ERROR_CODES)[number]) : null;
}

/** Σώμα's own wording for its errors, else the shared client wording. */
export function bodyErrorMessage(error: unknown, t: Translate, tUi: Parameters<typeof clientErrorMessage>[1]): string {
  const code = bodyErrorCode(error);
  return code ? t(["errors", code].join(".")) : clientErrorMessage(error, tUi);
}
