// The janitor's «Σήμερα» (ADR-202): what is due today and how far along it is.

export type DueRow = { space_id: string; cleanings_due: number; cleanings_done: number; done: boolean };
export type OpenEntry = { id: string; area_id: string };

export type DueStatus = "done" | "in_progress" | "due";

/** A space is in progress while the caller has an open cleaning of it. */
export function dueStatus(row: DueRow, open: OpenEntry[]): DueStatus {
  if (open.some((entry) => entry.area_id === row.space_id)) return "in_progress";
  return row.done ? "done" : "due";
}

/** What is left today, then what is done, keeping the server's order within each. */
export function orderDue<T extends DueRow>(rows: T[], open: OpenEntry[]): T[] {
  const rank: Record<DueStatus, number> = { in_progress: 0, due: 1, done: 2 };
  return rows
    .map((row, index) => ({ row, index }))
    .sort((a, b) => rank[dueStatus(a.row, open)] - rank[dueStatus(b.row, open)] || a.index - b.index)
    .map(({ row }) => row);
}

/** How many spaces are done out of how many are due. */
export function progress(rows: DueRow[]): { done: number; total: number } {
  return { done: rows.filter((row) => row.done).length, total: rows.length };
}

/** "HH:MM" of a schedule time ("07:00:00"). */
export function shortTime(time: string): string {
  return time.slice(0, 5);
}

/** A schedule's times typed as "07:00, 21:30": valid HH:MM only, sorted, without repeats. */
export function parseTimes(text: string): string[] | null {
  const parts = text
    .split(/[,\s]+/u)
    .map((part) => part.trim())
    .filter(Boolean);
  const valid = parts.every((part) => /^([01]\d|2[0-3]):[0-5]\d$/u.test(part));
  if (!valid) return null;
  return Array.from(new Set(parts)).sort();
}

/** Machine placement: what is left unassigned, and whether the rows fit what is owned. */
export function placementSummary(owned: number, rows: { quantity: number }[]) {
  const placed = rows.reduce((sum, row) => sum + (Number.isFinite(row.quantity) ? Math.max(0, row.quantity) : 0), 0);
  return { placed, unassigned: Math.max(owned - placed, 0), fits: placed <= owned };
}
