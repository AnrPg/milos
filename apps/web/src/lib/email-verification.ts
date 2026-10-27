// ADR-213: when the "confirm your email" banner shows. Pure, so it is unit-tested.

import { bottomNavHiddenRoute } from "@/lib/bottom-nav";

/** Where people change their email (Εγώ › Ρυθμίσεις › personal details). */
export const CHANGE_EMAIL_HREF = "/me/settings#personal";

/** The session key that hides the banner until the browser tab is closed. */
export const BANNER_DISMISS_KEY = "palee:email-verification-banner-hidden";

// Focused, full-screen flows keep their whole screen; the vendor console
// (where the one production account works) does show the banner.
const BANNER_HIDDEN_ROUTES = new Set([
  "workoutExecution",
  "freeTextExecution",
  "classTimer",
  "checkInKiosk",
  "checkInScan",
  "firstRun",
  "auth",
]);

/**
 * The banner shows to a signed-in person whose login has not confirmed its
 * email, unless hidden for this session. A user record without the field
 * (an older API) counts as confirmed, so nobody is nagged by mistake.
 */
export function showsVerificationBanner(input: {
  pathname: string;
  user: { email_verified?: boolean; email?: string } | null;
  dismissed: boolean;
}) {
  const { pathname, user, dismissed } = input;
  if (!user || dismissed || user.email_verified !== false || !user.email) return false;
  if (/^\/b(?:\/|$)/.test(pathname)) return false;
  const hidden = bottomNavHiddenRoute(pathname);
  return hidden === null || !BANNER_HIDDEN_ROUTES.has(hidden);
}

/** A throttled resend: a short wait in seconds, or "later" past a few minutes (the daily cap). */
export function retryWait(seconds: number): { kind: "seconds"; seconds: number } | { kind: "later" } {
  return seconds <= 300 ? { kind: "seconds", seconds } : { kind: "later" };
}
