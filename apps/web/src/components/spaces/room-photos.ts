/**
 * Moves the id at `index` one place earlier (-1) or later (1); returns the
 * new order of ids (ADR-290, room photos and cleaning points).
 */
export function moveItem(ids: string[], index: number, by: -1 | 1): string[] {
  const target = index + by;
  if (index < 0 || index >= ids.length || target < 0 || target >= ids.length) return ids;
  const next = [...ids];
  [next[index], next[target]] = [next[target], next[index]];
  return next;
}
