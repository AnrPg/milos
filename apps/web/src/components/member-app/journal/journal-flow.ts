import type { TrainingLogEntry } from "@/api/training-log";
import { entryDay, type HistoryEntry } from "@/components/client/vault";

/**
 * One entry of Ημερολόγιο › Ροή (brief §7.7): a completed execution or a
 * training-log entry. ADR-118 keeps the two disjoint (a class or assignment
 * counted by a completed execution cannot also be logged), so merging them
 * never shows the same session twice. Phase 1's `GetJournalFeed` (ADR-139)
 * adds PRs, injuries and reviews to the same stream server-side.
 */
export type JournalFlowItem =
  | { kind: "execution"; id: string; at: string; day: string; entry: HistoryEntry }
  | { kind: "log"; id: string; at: string; day: string; entry: TrainingLogEntry };

export type JournalFlowDay = { day: string; items: JournalFlowItem[] };

export function journalFlow(input: {
  executions: HistoryEntry[];
  logs: TrainingLogEntry[];
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
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at) || a.id.localeCompare(b.id));

  const days: JournalFlowDay[] = [];
  for (const item of items) {
    const last = days[days.length - 1];
    if (last && last.day === item.day) last.items.push(item);
    else days.push({ day: item.day, items: [item] });
  }
  return days;
}
