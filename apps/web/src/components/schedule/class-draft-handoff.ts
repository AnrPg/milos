/**
 * The class form a coach left for the WOD editor ("+ New WOD"), kept for this
 * tab only so the form reopens as it was when they come back, published WOD
 * or not. Stale or unreadable drafts are dropped; storage may be unavailable.
 */

const KEY = "palee.schedule.class-draft";
const MAX_AGE_MS = 6 * 60 * 60 * 1000;

export function stashClassDraft<T>(draft: T, now = Date.now()) {
  try {
    window.sessionStorage.setItem(KEY, JSON.stringify({ savedAt: now, draft }));
  } catch {}
}

export function takeClassDraft<T>(now = Date.now()): T | null {
  try {
    const raw = window.sessionStorage.getItem(KEY);
    window.sessionStorage.removeItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { savedAt?: unknown; draft?: T };
    if (typeof parsed.savedAt !== "number" || now - parsed.savedAt > MAX_AGE_MS) return null;
    return parsed.draft ?? null;
  } catch {
    return null;
  }
}
