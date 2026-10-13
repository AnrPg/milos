import { ApiError } from "@/api/client";
import { localizeError, type UiTranslator } from "@/i18n/presentation";

// Desk-specific wording for entitlement denials; the generic finance messages
// talk about coaching deliveries, which would confuse the front desk.
const CHECK_IN_ERROR_KEYS: Record<string, string> = {
  finance_profile_missing: "admCheckInNoActivePackage",
  finance_entitlement_inactive: "admCheckInNoActivePackage",
  finance_entitlement_plan_missing: "admCheckInNoActivePackage",
  finance_entitlement_blocked: "admCheckInBlocked",
  finance_channel_not_included: "admCheckInNoOpenGym",
  finance_capability_not_included: "admCheckInNoOpenGym",
  finance_allowance_not_included: "admCheckInNoOpenGym",
  finance_allowance_exhausted: "admCheckInAllowanceExhausted",
  finance_membership_frozen: "admCheckInFrozen",
  finance_location_not_included: "admCheckInLocationNotIncluded",
};

export function checkInErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return CHECK_IN_ERROR_KEYS[error.payload.code] ?? null;
}

export function localizeCheckInError(error: unknown, translate: UiTranslator) {
  const key = checkInErrorKey(error);
  return key ? translate(key) : localizeError(error, translate);
}
