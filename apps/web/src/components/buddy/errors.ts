import { ApiError } from "@/api/client";
import { clientErrorMessage } from "@/components/client/errors";

import { key } from "./buddy-model";

/** API error codes of Buddy για στήριξη (ADR-160) that have their own words. */
export const BUDDY_ERROR_CODES = [
  "buddy_limit_reached",
  "buddy_already_invited",
  "buddy_invite_expired",
  "buddy_link_closed",
  "buddy_invite_unavailable",
  "cannot_buddy_self",
  "not_eligible_for_buddy",
  "message_too_long",
  "support_rate_limited",
  "no_active_buddies",
  "already_undone",
  "undo_window_passed",
  "reply_text_required",
  "reply_too_long",
  "invalid_quiet_hours",
  "invalid_phone",
  "phone_required",
  "summary_required",
  "message_body_required",
  "message_too_long_body",
  "buddy_link_read_only",
] as const;

export type BuddyErrorCode = (typeof BUDDY_ERROR_CODES)[number];

export function buddyErrorCode(error: unknown): BuddyErrorCode | null {
  if (!(error instanceof ApiError) || !error.payload.code) return null;
  return (BUDDY_ERROR_CODES as readonly string[]).includes(error.payload.code) ? (error.payload.code as BuddyErrorCode) : null;
}

/** Buddy's own wording for its errors, else the shared client wording. */
export function buddyErrorMessage(error: unknown, t: (key: string) => string, tUi: Parameters<typeof clientErrorMessage>[1]): string | null {
  if (!error) return null;
  const code = buddyErrorCode(error);
  return code ? t(key("errors", code)) : clientErrorMessage(error, tUi);
}
