"use client";

import type { AuthTokens, CurrentUser } from "@/api/auth";

export const SESSION_STORAGE_KEY = "milos.auth.session";

export type StoredSession = {
  tokens: AuthTokens;
  currentUser: CurrentUser;
};

export function parseStoredSession(raw: string | null): StoredSession | null {
  if (!raw) return null;

  try {
    return JSON.parse(raw) as StoredSession;
  } catch {
    return null;
  }
}

export function readStoredSession(): StoredSession | null {
  if (typeof window === "undefined") return null;

  const raw = window.localStorage.getItem(SESSION_STORAGE_KEY);
  const session = parseStoredSession(raw);

  if (!session && raw) {
    window.localStorage.removeItem(SESSION_STORAGE_KEY);
    return null;
  }

  return session;
}

export function writeStoredSession(session: StoredSession) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
}

export function clearStoredSession() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(SESSION_STORAGE_KEY);
}
