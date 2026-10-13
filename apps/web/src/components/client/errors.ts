import { ApiError } from "@/api/client";
import { localizeError } from "@/i18n/presentation";

type Translate = Parameters<typeof localizeError>[1];

/** Phase C (ADR-098) API error codes the shared error map does not cover yet. */
const CLIENT_ERROR_KEYS: Record<string, string> = {
  form_review_closed: "clErrFormReviewClosed",
  appointment_slot_cancelled: "clErrApptCancelled",
  appointment_slot_in_past: "clErrApptStarted",
  appointment_slot_full: "clErrSlotFull",
  appointment_format_not_included: "clErrApptFormat",
  appointment_coach_not_included: "clErrApptCoach",
  appointment_not_active: "clErrApptNotActive",
  already_enrolled: "clErrCorporateAlready",
  corporate_seats_full: "clErrCorporateSeatsFull",
  corporate_enrollment_not_found: "clErrCorporateNotFound",
};

export function clientErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return CLIENT_ERROR_KEYS[error.payload.code] ?? null;
}

export function clientErrorMessage(error: unknown, translate: Translate): string {
  const key = clientErrorKey(error);
  return key ? translate(key) : localizeError(error, translate);
}
