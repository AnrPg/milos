"use client";

export const USER_SYNC_EVENT = "milos:user-sync";

export type UserSyncDetail = {
  user_id?: string;
  scopes: string[];
  reason?: string;
  payload?: Record<string, unknown>;
};

export function normalizeUserSyncDetail(value: unknown): UserSyncDetail | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }

  const scopes = Array.isArray((value as { scopes?: unknown }).scopes)
    ? (value as { scopes: unknown[] }).scopes.filter(
        (scope): scope is string => typeof scope === "string" && scope.length > 0,
      )
    : [];

  return {
    user_id: typeof (value as { user_id?: unknown }).user_id === "string" ? (value as { user_id: string }).user_id : undefined,
    scopes,
    reason: typeof (value as { reason?: unknown }).reason === "string" ? (value as { reason: string }).reason : undefined,
    payload:
      typeof (value as { payload?: unknown }).payload === "object" && (value as { payload?: unknown }).payload !== null
        ? ((value as { payload: Record<string, unknown> }).payload)
        : undefined,
  };
}

export function emitUserSync(detail: UserSyncDetail) {
  window.dispatchEvent(new CustomEvent<UserSyncDetail>(USER_SYNC_EVENT, { detail }));
}
