import { ApiError } from "@/api/client";

/** A message key under the `accountProfiles` namespace plus its values. */
export type AccountMessage = { key: string; values?: Record<string, string | number | Date> };

/** What a person types as a handle: no leading @, lower case, no spaces. */
export function cleanHandleInput(value: string) {
  return value.trim().replace(/^@+/, "").replace(/\s+/g, "").toLowerCase();
}

/** The server's rule (ADR-187), checked locally only to avoid pointless requests. */
export function looksLikeHandle(value: string) {
  return value.length >= 3 && value.length <= 30;
}

export function profileSlotsLeft(count: number, limit: number) {
  return Math.max(0, limit - count);
}

function firstMessage(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.find((entry): entry is string => typeof entry === "string") ?? null;
  return null;
}

/**
 * Maps the API's account errors (profile edit, add profile, recovery codes)
 * to friendly messages. Returns null for anything else, which the caller
 * shows through the app's generic error text.
 */
export function describeAccountError(error: unknown): AccountMessage | null {
  if (!(error instanceof ApiError)) return null;
  const payload = error.payload ?? {};

  switch (payload.code) {
    case "invalid_current_password":
      return { key: "errors.currentPassword" };
    case "profile_limit": {
      const limit = (payload as { profile_limit?: unknown }).profile_limit;
      return { key: "errors.profileLimit", values: { limit: typeof limit === "number" ? limit : 3 } };
    }
    case "email_in_use":
    case "email_taken":
      return { key: "errors.emailInUse" };
    case "weak_password":
      return { key: "errors.weakPassword" };
  }

  const errors = (payload.errors ?? {}) as Record<string, unknown>;
  const handleError = firstMessage(errors.handle) ?? firstMessage(errors.nickname);
  if (handleError) {
    const date = handleError.match(/(\d{4}-\d{2}-\d{2})/)?.[1];
    if (/changed again/i.test(handleError) && date) {
      return { key: "errors.handleCooldown", values: { date: new Date(`${date}T12:00:00Z`) } };
    }
    if (/taken|reserved/i.test(handleError)) return { key: "errors.handleTaken" };
    return { key: "errors.handleInvalid" };
  }
  if (firstMessage(errors.display_name)) return { key: "errors.displayNameInvalid" };
  if (firstMessage(errors.email)) {
    return /taken|already/i.test(firstMessage(errors.email) ?? "")
      ? { key: "errors.emailInUse" }
      : { key: "errors.emailInvalid" };
  }
  if (firstMessage(errors.password)) return { key: "errors.weakPassword" };
  if (firstMessage(errors.current_password)) return { key: "errors.currentPassword" };
  return null;
}

/** The body of the downloadable recovery-codes file, one code per line. */
export function recoveryCodesFileText({
  heading,
  account,
  generatedAt,
  note,
  codes,
}: {
  heading: string;
  account: string;
  generatedAt: string;
  note: string;
  codes: string[];
}) {
  return [heading, account, generatedAt, "", ...codes, "", note, ""].join("\n");
}

export function recoveryCodesFileName(handle: string | null | undefined, date: Date) {
  const day = date.toISOString().slice(0, 10);
  const safeHandle = (handle ?? "").replace(/[^a-z0-9._]/gi, "");
  return `palee-recovery-codes${safeHandle ? `-${safeHandle}` : ""}-${day}.txt`;
}

/** Saves a small text file in the browser (and the Capacitor web view). */
export function downloadTextFile(fileName: string, text: string) {
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
