import type { ReviewRecord } from "@/api/reviews";
import type { TrainingLogEntry } from "@/api/training-log";
import { entryDay, type HistoryEntry } from "@/components/client/vault";

/**
 * One entry of Ημερολόγιο › Ροή (brief §7.7): a completed execution, a
 * training-log entry or a review the member wrote. ADR-118 keeps executions
 * and log entries disjoint (a class or assignment counted by a completed
 * execution cannot also be logged), so merging them never shows the same
 * session twice. Reviews have no tab of their own: they live here, dated by
 * when they were written. `GetJournalFeed` (ADR-139) moves this merge
 * server-side and adds PRs and injuries.
 */
export type JournalFlowItem =
  | { kind: "execution"; id: string; at: string; day: string; entry: HistoryEntry }
  | { kind: "log"; id: string; at: string; day: string; entry: TrainingLogEntry }
  | { kind: "review"; id: string; at: string; day: string; entry: ReviewRecord };

export type JournalFlowDay = { day: string; items: JournalFlowItem[] };

export function journalFlow(input: {
  executions: HistoryEntry[];
  logs: TrainingLogEntry[];
  reviews?: ReviewRecord[];
  fallbackTimeZone?: string;
}): JournalFlowDay[] {
  const items: JournalFlowItem[] = [
    ...input.executions.map((entry) => ({
      kind: "execution" as const,
      id: `execution:${entry.id}`,
      at: entry.completed_at_utc,
      day: entry.day,
      entry,
    })),
    ...input.logs.map((entry) => ({
      kind: "log" as const,
      id: `log:${entry.id}`,
      at: entry.performed_at_utc,
      day: entryDay(entry.performed_at_utc, entry.performed_at_tz, input.fallbackTimeZone),
      entry,
    })),
    ...(input.reviews ?? []).map((entry) => ({
      kind: "review" as const,
      id: `review:${entry.id}`,
      at: entry.inserted_at,
      day: entryDay(entry.inserted_at, null, input.fallbackTimeZone),
      entry,
    })),
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at) || a.id.localeCompare(b.id));

  const days: JournalFlowDay[] = [];
  for (const item of items) {
    const last = days[days.length - 1];
    if (last && last.day === item.day) last.items.push(item);
    else days.push({ day: item.day, items: [item] });
  }
  return days;
}
