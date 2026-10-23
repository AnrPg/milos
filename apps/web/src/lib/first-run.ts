/**
 * The member first-run after sign-up (ADR-183). Finishing or skipping it
 * records the `first_run` tour on the account, so no device shows it again;
 * the session flag covers the moments before /auth/me is read again.
 */
export const FIRST_RUN = "first_run";

const doneKey = (userId: string) => `palee:first-run-done:${userId}`;

type FirstRunUser = { id: string; vendor?: boolean | null; completed_tours?: string[] | null };

export function needsFirstRun(user: FirstRunUser | null | undefined): boolean {
  if (!user || user.vendor) return false;
  if (user.completed_tours?.includes(FIRST_RUN)) return false;
  try {
    return window.sessionStorage.getItem(doneKey(user.id)) !== "1";
  } catch {
    return true;
  }
}

export function markFirstRunDone(userId: string) {
  try {
    window.sessionStorage.setItem(doneKey(userId), "1");
  } catch {}
}

/** Only same-site paths, so `?next=` can never send someone off Palee. */
export function safeNext(next: string | null | undefined): string {
  return next && next.startsWith("/") && !next.startsWith("//") ? next : "/";
}
