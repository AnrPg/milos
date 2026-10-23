/**
 * "New WOD" from inside another form (the class editor): the WOD editor opens
 * as its usual page with `?return_to=<path>`, and publishing sends the coach
 * back there with `?wod=<id>`, so the form reopens with the new WOD chosen.
 */

export const WORKOUT_RETURN_PARAM = "return_to";
export const RETURNED_WORKOUT_PARAM = "wod";

/** Only a path inside this app: never another origin or a protocol-relative URL. */
export function safeReturnPath(raw: string | null | undefined): string | null {
  if (!raw || !raw.startsWith("/") || raw.startsWith("//") || raw.startsWith("/\\")) return null;
  try {
    const url = new URL(raw, "http://palee.local");
    if (url.origin !== "http://palee.local") return null;
    return `${url.pathname}${url.search}`;
  } catch {
    return null;
  }
}

/** The WOD editor's address for a coach who should come back to `returnPath`. */
export function newWorkoutHref(newWorkoutPath: string, returnPath: string) {
  const separator = newWorkoutPath.includes("?") ? "&" : "?";
  return `${newWorkoutPath}${separator}${WORKOUT_RETURN_PARAM}=${encodeURIComponent(returnPath)}`;
}

/** Where publishing goes: back to the form with the WOD, else `fallback`. */
export function workoutPublishedHref(
  searchParams: Pick<URLSearchParams, "get">,
  workoutId: string,
  fallback: string,
) {
  const returnPath = safeReturnPath(searchParams.get(WORKOUT_RETURN_PARAM));
  if (!returnPath) return fallback;
  const url = new URL(returnPath, "http://palee.local");
  url.searchParams.set(RETURNED_WORKOUT_PARAM, workoutId);
  return `${url.pathname}${url.search}`;
}
