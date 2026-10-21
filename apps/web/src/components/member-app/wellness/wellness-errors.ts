import { ApiError } from "@/api/client";
import { localizeError } from "@/i18n/presentation";

type Translate = Parameters<typeof localizeError>[1];

/** Wellness API codes with their own wording (MemberApp.wellness.error.*). */
export const WELLNESS_ERROR_CODES = [
  "health_data_consent_required",
  "occurred_in_future",
  "occurred_too_long_ago",
  "invalid_wellness_value",
  "invalid_media",
] as const;

export function wellnessErrorMessage(error: unknown, t: (key: string) => string, ui: Translate): string | null {
  if (!error) return null;
  const code = error instanceof ApiError ? error.payload.code : null;
  if (code && (WELLNESS_ERROR_CODES as readonly string[]).includes(code)) return t(`error.${code}`);
  return localizeError(error, ui);
}
