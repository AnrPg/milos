// The member app's floating bottom bar (brief §6.1, owner's call of
// 2026-10-23): Feed · Box · Ημερολόγιο · Ειδοποιήσεις · avatar (Εγώ). What it
// holds, where it never shows, and who gets it. Pure, so it is unit-tested.

import { clientNavItems, type NavItem } from "@/lib/role-navigation";

/**
 * The bell sits in the bar, next to the avatar. Set to false for the 4-tab
 * fallback: the bar keeps the four tabs and the bell goes back to the Feed
 * header (♡ next to ✈), with nothing else to change.
 */
export const BELL_IN_BOTTOM_NAV = true;

export type BottomNavEntry =
  | { kind: "tab"; item: NavItem }
  | { kind: "notifications" }
  | { kind: "me"; item: NavItem };

/**
 * The bar's entries in order. Box is always there (brief §6.1: the four tabs
 * are fixed); without a box it opens its empty "find a box" state.
 */
export function bottomNavEntries(bellInBar: boolean = BELL_IN_BOTTOM_NAV): BottomNavEntry[] {
  const items = clientNavItems();
  const me = items.find((item) => item.id === "me")!;
  return [
    ...items.filter((item) => item.id !== "me").map((item) => ({ kind: "tab" as const, item })),
    ...(bellInBar ? [{ kind: "notifications" as const }] : []),
    { kind: "me" as const, item: me },
  ];
}

/**
 * Focused, full-screen flows where the bar never shows (the registry). A
 * screen that is not a route of its own (a full-screen layer, the composer,
 * the camera, a media preview, the avatar editor) asks with
 * useHideBottomNav() instead; ui/Layer and ui/Dialog do it for every layer.
 * Signed-out visitors (public box pages, auth pages) never get the bar.
 */
export const BOTTOM_NAV_HIDDEN_ROUTES: ReadonlyArray<{ id: string; pattern: RegExp }> = [
  // Workout execution: the live session and its timers (brief §7.4: unchanged).
  { id: "workoutExecution", pattern: /^\/workouts\/[^/]+\/execute(?:\/|$)/ },
  { id: "freeTextExecution", pattern: /^\/workouts\/free-text\/execute(?:\/|$)/ },
  // The class timer on the gym's screen and the coach's remote.
  { id: "classTimer", pattern: /^\/class-timer\/[^/]+\/(?:display|control)(?:\/|$)/ },
  // The check-in desk: the door kiosk, the printed poster, and the scan landing.
  { id: "checkInKiosk", pattern: /^\/admin\/check-in\/(?:door|poster)\/[^/]+\/?$/ },
  { id: "checkInScan", pattern: /^\/c\/[^/]+(?:\/|$)/ },
  // Onboarding / first run.
  { id: "firstRun", pattern: /^\/welcome(?:\/|$)/ },
  // Auth and account set-up.
  { id: "auth", pattern: /^\/(?:login|register|forgot-password|reset-password|set-admin|activate-business|join)(?:\/|$)/ },
  // The vendor console has its own navigation.
  { id: "platform", pattern: /^\/platform(?:\/|$)/ },
];

function relativePath(pathname: string) {
  return pathname.replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/";
}

/** The registry entry that hides the bar on `pathname`, if any. */
export function bottomNavHiddenRoute(pathname: string) {
  const path = relativePath(pathname.split(/[?#]/)[0]);
  return BOTTOM_NAV_HIDDEN_ROUTES.find((route) => route.pattern.test(path))?.id ?? null;
}

export function routeShowsBottomNav(pathname: string) {
  return bottomNavHiddenRoute(pathname) === null;
}

/**
 * Who gets the member shell (the bar instead of the top bar): a signed-in
 * member or athlete, or an account without a box yet (Box then shows its
 * find-a-box state). Staff views, the vendor without a box and an account
 * admin waiting for its box keep the top bar.
 */
export function usesMemberShell(input: {
  signedIn: boolean;
  loading: boolean;
  membershipCount: number;
  surfaceRole: string;
  vendor: boolean;
  accountRole?: string | null;
}) {
  if (!input.signedIn || input.loading) return false;
  if (input.membershipCount > 0) return input.surfaceRole !== "admin";
  return !input.vendor && input.accountRole !== "admin";
}

/** Instagram-like: hide while scrolling down, show again on any scroll up or near the top. */
export function nextScrollHidden(previous: { hidden: boolean; lastY: number }, y: number, threshold = 8) {
  if (y < 56) return false;
  const delta = y - previous.lastY;
  if (Math.abs(delta) < threshold) return previous.hidden;
  return delta > 0;
}
