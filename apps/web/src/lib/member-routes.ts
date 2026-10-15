// Redesign Phase 1 (ADR-137): member pages moved under the tab that is now
// their home. Old URLs redirect (next.config.ts) and old links stored
// server-side, such as notification payloads, are mapped here. Most specific
// first: the first matching prefix wins.
export const MEMBER_ROUTE_MOVES: ReadonlyArray<readonly [from: string, to: string]> = [
  ["/my-workouts/history", "/journal"],
  ["/my-workouts/pantheon", "/journal/pantheon"],
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
  ["/account/activity", "/me/activity"],
];

/** The current location of a member path that may predate the move; anything else is returned as is. */
export function currentMemberPath(path: string): string {
  const match = path.match(/^(\/org\/[^/?#]+)?(\/[^?#]*)?(.*)$/);
  if (!match) return path;
  const [, orgPrefix = "", pathname = "/", rest = ""] = match;
  for (const [from, to] of MEMBER_ROUTE_MOVES) {
    if (pathname === from || pathname.startsWith(from + "/")) {
      return orgPrefix + to + pathname.slice(from.length) + rest;
    }
  }
  return path;
}
