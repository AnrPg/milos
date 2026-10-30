// Relative, not `@/`: next.config.ts loads this file too.
import { KIND_ORDER } from "../components/around/around";

// Redesign Phase 1 (ADR-137): member pages moved under the tab that is now
// their home. Old URLs redirect (next.config.ts) and old links stored
// server-side, such as notification payloads, are mapped here. Most specific
// first: the first matching prefix wins.
export const MEMBER_ROUTE_MOVES: ReadonlyArray<readonly [from: string, to: string]> = [
  ["/my-workouts/history", "/journal"],
  // PRs are a section of Πρόοδος, not «Pantheon» (ANR 2026-10-24).
  ["/journal/pantheon", "/journal/progress"],
  ["/my-workouts/pantheon", "/journal/progress"],
  ["/my-workouts", "/box/workouts"],
  ["/schedule", "/box/schedule"],
  ["/appointments", "/box/appointments"],
  ["/videos", "/box/videos"],
  ["/coaching", "/box/coach"],
  ["/progress", "/journal/progress"],
  ["/wellbeing", "/journal/wellbeing"],
  ["/reviews", "/journal/reviews"],
  ["/profile", "/me/settings"],
  ["/account/billing", "/me/payments"],
  // ADR-196: one inbox. The old chats page and ADR-193's person
  // conversations both open /messages (?thread=, ?folder=, /:id kept).
  ["/account/activity/chats", "/messages"],
  ["/me/activity/chats", "/messages"],
  ["/me/messages", "/messages"],
  ["/account/activity", "/me/activity"],
  // ADR-196: paths the API's notifications used to name.
  ["/box/shop/products", "/box/shop/product"],
  ["/journal/wellness", "/journal/wellbeing"],
];

/**
 * Old paths with no page of their own that open a place on another page
 * (ADR-196). Exact matches only. `/partners` is the public deck again
 * (ADR-280), so it no longer moves to Μηνύματα › Partners.
 */
export const MEMBER_EXACT_MOVES: ReadonlyArray<readonly [from: string, to: string]> = [
  ["/me/settings/export", "/me/settings#journal-export"],
];

// Γύρω μου's «Δες όλα» narrows «what» in place (vision §7.2), so the old
// one-kind pages `/around/<kind>` open Γύρω μου with that kind preselected.
const AROUND_KIND_PATTERN = `:kind(${KIND_ORDER.join("|")})`;
export const AROUND_KIND_REDIRECTS: ReadonlyArray<{ source: string; destination: string }> = [
  { source: `/around/${AROUND_KIND_PATTERN}`, destination: "/around?kind=:kind" },
  { source: `/org/:organization_slug/around/${AROUND_KIND_PATTERN}`, destination: "/org/:organization_slug/around?kind=:kind" },
];

/** The current location of a member path that may predate the move; anything else is returned as is. */
export function currentMemberPath(path: string): string {
  const match = path.match(/^(\/org\/[^/?#]+)?(\/[^?#]*)?(.*)$/);
  if (!match) return path;
  const [, orgPrefix = "", pathname = "/", rest = ""] = match;
  for (const [from, to] of MEMBER_EXACT_MOVES) {
    if (pathname === from) return orgPrefix + to;
  }
  for (const [from, to] of MEMBER_ROUTE_MOVES) {
    if (pathname === from || pathname.startsWith(from + "/")) {
      return orgPrefix + to + pathname.slice(from.length) + rest;
    }
  }
  return path;
}
