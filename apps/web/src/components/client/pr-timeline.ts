import type { PRTimelineEntry } from "@/api/content";
import { formatScore } from "@/components/pantheon/PantheonCard";
import type { PRUnit } from "@/api/gamification";

export type PRTimelineMonth<T extends PRTimelineEntry = PRTimelineEntry> = { month: string; entries: T[] };

/** Timeline entries grouped by `YYYY-MM`, newest month and newest entry first. */
export function groupPRTimelineByMonth<T extends PRTimelineEntry>(entries: T[]): PRTimelineMonth<T>[] {
  const ordered = [...entries].sort((a, b) => b.beaten_on.localeCompare(a.beaten_on));
  const months: PRTimelineMonth<T>[] = [];
  for (const entry of ordered) {
    const month = entry.beaten_on.slice(0, 7);
    const last = months[months.length - 1];
    if (last && last.month === month) last.entries.push(entry);
    else months.push({ month, entries: [entry] });
  }
  return months;
}

/** Score as the Pantheon shows it (`mm:ss` for times). */
export function formatPRScore(score: number, unit: string): string {
  return formatScore(score, unit as PRUnit);
}

export type PRImprovement =
  | { kind: "first" }
  /** Time saved, already formatted `mm:ss`. */
  | { kind: "time_saved"; text: string }
  /** Signed amount in the PR's unit, e.g. `+5` or `−2.50`. */
  | { kind: "amount"; text: string };

/**
 * How much a beaten PR improved. A first record has no previous score; time
 * PRs where lower is better report the time saved.
 */
export function prImprovement(entry: PRTimelineEntry): PRImprovement {
  const previous = entry.previous_score;
  const delta =
    previous != null ? entry.score - previous : entry.change != null ? entry.change : null;
  if (previous == null && entry.change == null) return { kind: "first" };
  if (delta == null) return { kind: "first" };

  const amount = Math.abs(delta);
  if (entry.unit === "mins_secs" && entry.higher_is_better === false) {
    return { kind: "time_saved", text: formatPRScore(amount, entry.unit) };
  }
  const sign = delta < 0 ? "−" : "+";
  return { kind: "amount", text: `${sign}${formatPRScore(amount, entry.unit)}` };
}
