/**
 * ADR-201: one WOD variation for several people at once. Each person is
 * programmed as if they were the only one; these pure rules pick who can be
 * chosen and read the per-person outcome.
 */

import { ApiError } from "@/api/client";
import type { ProgramForUsersResult } from "@/api/admin-users";

/** The most people one request may program (the API refuses more). */
export const GROUP_PROGRAMMING_LIMIT = 50;

export type VariationCandidate = {
  userId: string;
  nickname: string;
  /** Already has their own version of this class (ADR-125). */
  hasVersion: boolean;
};

type BookingLike = {
  user_id: string;
  user_nickname?: string | null;
  status: string;
  guest_name?: string | null;
};

/**
 * The people of a class who can get a variation: approved or pending
 * bookings, each person once, guests left out (a guest has no account of
 * their own; the booking belongs to the host).
 */
export function variationCandidates(
  bookings: readonly BookingLike[],
  memberVersions: readonly { user_id: string }[] = [],
): VariationCandidate[] {
  const withVersion = new Set(memberVersions.map((version) => version.user_id));
  const seen = new Set<string>();
  const candidates: VariationCandidate[] = [];

  for (const booking of bookings) {
    if (booking.status !== "approved" && booking.status !== "pending") continue;
    if (booking.guest_name) continue;
    if (!booking.user_id || seen.has(booking.user_id)) continue;
    seen.add(booking.user_id);
    candidates.push({
      userId: booking.user_id,
      nickname: booking.user_nickname || booking.user_id,
      hasVersion: withVersion.has(booking.user_id),
    });
  }

  return candidates.sort((a, b) => a.nickname.localeCompare(b.nickname));
}

/**
 * The day a class variant is filed under. The API checks the booking within
 * that UTC day, so it is the class's UTC date, not the viewer's local one.
 */
export function classDay(scheduledAt: string): string {
  const date = new Date(scheduledAt);
  return Number.isNaN(date.getTime()) ? scheduledAt.slice(0, 10) : date.toISOString().slice(0, 10);
}

/** Adds or removes one person, never past the limit. */
export function toggleSelection(selected: readonly string[], userId: string, limit = GROUP_PROGRAMMING_LIMIT): string[] {
  if (selected.includes(userId)) return selected.filter((id) => id !== userId);
  if (selected.length >= limit) return [...selected];
  return [...selected, userId];
}

export type GroupOutcomeRow = {
  userId: string;
  nickname: string;
  ok: boolean;
  /** The error as the one-person endpoint would have answered it. */
  error?: ApiError;
};

const ERROR_STATUS: Record<string, number> = {
  not_found: 404,
  slot_not_found: 404,
  workout_not_found: 404,
  not_your_client: 403,
  forbidden: 403,
  programming_not_in_package: 403,
};

/**
 * One row per person, in the order the API answered. A failure carries an
 * ApiError so it is localized with the same keys as a one-person failure.
 */
export function groupOutcomeRows(
  results: readonly ProgramForUsersResult[],
  nicknames: ReadonlyMap<string, string>,
): GroupOutcomeRow[] {
  return results.map((result) => {
    const nickname = nicknames.get(result.user_id) ?? result.user_id;
    if (result.status === "ok") return { userId: result.user_id, nickname, ok: true };

    const code = result.code ?? "unexpected_server_error";
    const status = ERROR_STATUS[code] ?? (code === "unexpected_server_error" ? 500 : 422);
    const error = new ApiError(status, code, {
      code,
      params: (result.params ?? undefined) as Record<string, unknown> | undefined,
    });
    return { userId: result.user_id, nickname, ok: false, error };
  });
}

/** How many people got it and how many did not. */
export function outcomeCounts(rows: readonly GroupOutcomeRow[]) {
  const succeeded = rows.filter((row) => row.ok).length;
  return { succeeded, failed: rows.length - succeeded };
}
