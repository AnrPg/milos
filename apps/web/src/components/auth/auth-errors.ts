import { ApiError } from "@/api/client";

/** A next-intl translator for one namespace. */
export type Translate = (key: string, values?: Record<string, string | number>) => string;
export type FieldErrors = Record<string, string[]>;

/** What a failed sign-up shows: messages under their fields, or one message for the form. */
export type AuthFailure = { fieldErrors: FieldErrors; message: string | null };

const DEFAULT_PROFILE_LIMIT = 3;

function numberOr(value: unknown, fallback: number | null) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function messagesOf(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
}

/**
 * ADR-187: an email holds up to three profiles. The API only says how many,
 * never which ones (the list is shown after sign-in).
 */
function emailInUseMessage(payload: Record<string, unknown>, t: Translate) {
  const limit = numberOr(payload.profile_limit, DEFAULT_PROFILE_LIMIT) ?? DEFAULT_PROFILE_LIMIT;
  const count = numberOr(payload.profile_count, null);

  if (count === null) return t("emailInUseUnknown");
  if (count >= limit) return t("emailLimitReached", { limit });
  return `${t("emailInUseCount", { count, limit })} ${t("emailInUseAddProfile")}`;
}

function fieldMessage(field: string, raw: string[], t: Translate): string | null {
  const taken = raw.some((message) => /taken|already/i.test(message));

  switch (field) {
    case "handle":
    case "nickname":
      return taken ? t("handleTakenError") : t("handleRule");
    case "display_name":
      return t("displayNameRule");
    case "email":
      return taken ? t("emailInUseUnknown") : t("emailInvalid");
    case "password":
      return t("passwordRule");
    default:
      return null;
  }
}

/**
 * Maps a failed sign-up to messages under its fields: 409 `email_in_use`,
 * 422 `profile_limit` and per-field validation errors. Anything else goes to
 * `fallback` as one form-level message.
 */
export function registerFailure(
  error: unknown,
  t: Translate,
  fallback: (error: unknown) => string,
  genericField: string,
): AuthFailure {
  if (!(error instanceof ApiError)) return { fieldErrors: {}, message: fallback(error) };

  const payload = error.payload as Record<string, unknown>;

  if (error.payload.code === "email_in_use") {
    return { fieldErrors: { email: [emailInUseMessage(payload, t)] }, message: null };
  }

  if (error.payload.code === "profile_limit") {
    const limit = numberOr(payload.profile_limit, DEFAULT_PROFILE_LIMIT) ?? DEFAULT_PROFILE_LIMIT;
    return { fieldErrors: { email: [t("emailLimitReached", { limit })] }, message: null };
  }

  if (error.payload.code === "weak_password") {
    return { fieldErrors: { password: [t("passwordRule")] }, message: null };
  }

  const fieldErrors: FieldErrors = {};
  for (const [field, value] of Object.entries(error.payload.errors ?? {})) {
    const raw = messagesOf(value);
    if (raw.length === 0) continue;
    const key = field === "nickname" ? "handle" : field;
    fieldErrors[key] = [fieldMessage(field, raw, t) ?? genericField];
  }

  return Object.keys(fieldErrors).length > 0
    ? { fieldErrors, message: null }
    : { fieldErrors: {}, message: fallback(error) };
}

export type ResetFailure = "invalid" | "expired" | "weak_password" | "other";

/** The reset-link page tells an expired link (410) from an unknown or used one (422). */
export function resetFailure(error: unknown): ResetFailure {
  if (!(error instanceof ApiError)) return "other";
  if (error.status === 410 || error.payload.code === "expired_reset_link") return "expired";
  if (error.payload.code === "invalid_reset_link") return "invalid";
  if (error.payload.code === "weak_password") return "weak_password";
  return "other";
}

/** The token of a reset link travels in the fragment (`#token=...`) so it never reaches server logs. */
export function resetTokenFromHash(hash: string): string | null {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const token = params.get("token")?.trim();
  return token ? token : null;
}

/** What someone types as a handle: a leading "@" and spaces dropped; the server folds the rest. */
export function handleInput(value: string) {
  return value.replace(/\s+/g, "").replace(/^@+/, "");
}

export const MIN_PASSWORD_LENGTH = 4;

/** ANR's rule: at least 4 characters that are not whitespace (spaces still allowed). Mirrors the API. */
export function passwordLongEnough(password: string) {
  return Array.from(password.replace(/\s/gu, "")).length >= MIN_PASSWORD_LENGTH;
}
