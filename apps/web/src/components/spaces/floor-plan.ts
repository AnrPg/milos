// Floor plans and the areas of spaces drawn on them (ADR-202). Areas are
// polygons in normalized coordinates (0..1, origin top-left) so they scale
// with the image; the editor draws rectangles (four points).

export type Point = [number, number];
export type Area = { points: Point[] | number[][] };

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));
const round4 = (value: number) => Math.round(value * 10_000) / 10_000;

/** A pointer position over an element's box, normalized and clamped to 0..1. */
export function normalizedPoint(clientX: number, clientY: number, box: { left: number; top: number; width: number; height: number }): Point {
  if (box.width <= 0 || box.height <= 0) return [0, 0];
  return [round4(clamp01((clientX - box.left) / box.width)), round4(clamp01((clientY - box.top) / box.height))];
}

/** Smallest rectangle side, so a click is not mistaken for a drawing. */
export const MIN_SIDE = 0.02;

/** The rectangle dragged from `start` to `end`, or null when it is too small to be meant. */
export function rectangleFromDrag(start: Point, end: Point): Point[] | null {
  const left = Math.min(start[0], end[0]);
  const right = Math.max(start[0], end[0]);
  const top = Math.min(start[1], end[1]);
  const bottom = Math.max(start[1], end[1]);
  if (right - left < MIN_SIDE || bottom - top < MIN_SIDE) return null;
  return [
    [round4(left), round4(top)],
    [round4(right), round4(top)],
    [round4(right), round4(bottom)],
    [round4(left), round4(bottom)],
  ];
}

/** SVG `points` on a 100×100 viewBox. */
export function svgPoints(points: number[][]): string {
  return points.map(([x, y]) => `${round4(x * 100)},${round4(y * 100)}`).join(" ");
}

/** Where a label goes: the centre of the area's bounding box, on the 100×100 viewBox. */
export function labelPosition(points: number[][]): { x: number; y: number } {
  if (points.length === 0) return { x: 50, y: 50 };
  const xs = points.map(([x]) => x);
  const ys = points.map(([, y]) => y);
  return { x: round4(((Math.min(...xs) + Math.max(...xs)) / 2) * 100), y: round4(((Math.min(...ys) + Math.max(...ys)) / 2) * 100) };
}

/** Whether an area is a usable polygon (3 or more points within the plan). */
export function validArea(area: Area | null | undefined): area is Area {
  return Boolean(
    area &&
      Array.isArray(area.points) &&
      area.points.length >= 3 &&
      area.points.every((point) => Array.isArray(point) && point.length === 2 && point.every((value) => value >= 0 && value <= 1)),
  );
}

type Placed = { id: string; floor_plan_id?: string | null; area?: Area | null };

/** The spaces drawn on one floor plan. */
export function spacesOnPlan<T extends Placed>(spaces: T[], planId: string): T[] {
  return spaces.filter((space) => space.floor_plan_id === planId && validArea(space.area));
}

type Located = { location_id?: string | null };

/** Groups by branch: one group per location id (null for spaces of the whole gym), in `order`. */
export function groupByBranch<T extends Located>(items: T[], order: (string | null)[]): { locationId: string | null; items: T[] }[] {
  const keys = [...order];
  for (const item of items) {
    const key = item.location_id ?? null;
    if (!keys.includes(key)) keys.push(key);
  }
  return keys
    .map((locationId) => ({ locationId, items: items.filter((item) => (item.location_id ?? null) === locationId) }))
    .filter((group) => group.items.length > 0 || order.includes(group.locationId));
}

type Branchy = { location_id?: string | null; archived_at?: string | null };

/**
 * The spaces a class at these branches can take: gym-wide spaces always, a
 * branch's own only when the class is at that one branch. Archived ones never.
 */
export function spacesForBranches<T extends Branchy>(spaces: T[], locationIds: (string | null | undefined)[]): T[] {
  const branches = Array.from(new Set(locationIds.map((id) => id ?? null)));
  const only = branches.length === 1 ? branches[0] : null;
  return spaces.filter((space) => !space.archived_at && ((space.location_id ?? null) === null || (only !== null && space.location_id === only)));
}

/** Whether a window is still current or ahead at `now`. */
export function upcomingWindow(window: { ends_at: string }, now: Date = new Date()) {
  return new Date(window.ends_at).getTime() > now.getTime();
}

/** «Μη διαθέσιμος» form: both ends set and the end after the start. */
export function windowReady(startsAt: string | null, endsAt: string | null) {
  return Boolean(startsAt && endsAt && new Date(endsAt).getTime() > new Date(startsAt).getTime());
}
