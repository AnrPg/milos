import type { EntryAudience, JournalFeedItem, JournalFeedPage, JournalVisibilityResult, TypedJournalItem } from "@/api/journal";
import { typedItem } from "@/api/journal";
import { entryDay, type HistoryEntry } from "@/components/client/vault";

/**
 * Ημερολόγιο › Ροή (brief §7.7, ADR-139): the server's feed of every entry
 * kind, newest first, grouped by the day each entry happened on. The day is
 * the entry's own (in the zone it was recorded in, or the date a PR was
 * beaten), so a late-evening session stays on its day.
 */
export type JournalFlowDay = { day: string; items: TypedJournalItem[] };

export function itemDay(item: JournalFeedItem, fallbackTimeZone?: string): string {
  return item.occurred_on ?? entryDay(item.occurred_at, item.occurred_tz, fallbackTimeZone);
}

export function journalFlow(pages: JournalFeedPage[], fallbackTimeZone?: string): JournalFlowDay[] {
  const seen = new Set<string>();
  const days: JournalFlowDay[] = [];

  for (const item of pages.flatMap((page) => page.items)) {
    const key = `${item.kind}:${item.id}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const day = itemDay(item, fallbackTimeZone);
    const last = days[days.length - 1];
    if (last && last.day === day) last.items.push(typedItem(item));
    else days.push({ day, items: [typedItem(item)] });
  }
  return days;
}

/** The feed pages with one entry's new rung, as the server answered the move. */
export function withVisibility(pages: JournalFeedPage[], result: JournalVisibilityResult): JournalFeedPage[] {
  return pages.map((page) => ({
    ...page,
    items: page.items.map((item) =>
      item.kind === result.kind && item.id === result.id
        ? {
            ...item,
            journal_visibility: result.journal_visibility,
            choosable_visibilities: result.choosable_visibilities as JournalFeedItem["choosable_visibilities"],
          }
        : item,
    ),
  }));
}

/** The feed pages with one entry's coach audience, as the server answered. */
export function withAudience(
  pages: JournalFeedPage[],
  target: Pick<JournalFeedItem, "kind" | "id">,
  audience: EntryAudience | null,
): JournalFeedPage[] {
  return pages.map((page) => ({
    ...page,
    items: page.items.map((item) => (item.kind === target.kind && item.id === target.id ? { ...item, audience } : item)),
  }));
}

/** A finished execution in the shape the vault rows use (performance, repeat, share). */
export function executionHistoryEntry(
  item: Extract<TypedJournalItem, { kind: "execution" }>,
  day: string,
): HistoryEntry {
  const execution = item.entry;
  return {
    id: execution.id,
    started_at_utc: execution.started_at_utc,
    completed_at_utc: execution.completed_at_utc ?? item.occurred_at,
    completed_at_tz: execution.completed_at_tz ?? null,
    scale_level_slug: execution.scale_level_slug ?? null,
    source: execution.source,
    total_elapsed_ms: execution.total_elapsed_ms,
    master_workout_id: execution.master_workout_id ?? "",
    workout_title: execution.workout_title ?? null,
    workout_type: execution.workout_type ?? null,
    season: execution.season ?? null,
    day,
  } as HistoryEntry;
}
