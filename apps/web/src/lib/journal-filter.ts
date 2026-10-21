import {
  EMPTY_JOURNAL_FILTER,
  type JournalFeedFilter,
  type JournalKind,
  type JournalVisibility,
} from "@/api/journal";

/**
 * Ημερολόγιο › Ροή filter on the client (ADR-162 `JournalFilter` v1): read a
 * remembered filter defensively (an older or newer shape never breaks the
 * page), count facets for «Φίλτρα (n)» exactly as the server does, and tell
 * whether two filters ask for the same feed.
 */
export const JOURNAL_KINDS: JournalKind[] = [
  "execution",
  "training_log",
  "pr",
  "note",
  "check_in",
  "injury",
  "review",
  "body",
  "wellness",
  "craving",
];

export const JOURNAL_VISIBILITIES: JournalVisibility[] = [
  "private",
  "coach_can_view",
  "coach_reply_requested",
  "rated",
  "posted",
];

const FILTER_VERSION = 1;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function strings(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === "string");
  if (typeof value === "string") return value.split(",").filter(Boolean);
  return [];
}

function day(value: unknown): string | null {
  return typeof value === "string" && DATE.test(value) ? value : null;
}

export function parseJournalFilter(params: Record<string, unknown> | null | undefined): JournalFeedFilter {
  if (!params || (params.v !== undefined && params.v !== FILTER_VERSION)) return EMPTY_JOURNAL_FILTER;
  const q = typeof params.q === "string" && params.q.trim().length >= 2 ? params.q.trim().slice(0, 100) : null;
  return {
    kinds: strings(params.kinds).filter((kind): kind is JournalKind => JOURNAL_KINDS.includes(kind as JournalKind)),
    sources: strings(params.sources),
    visibilities: strings(params.visibilities).filter((rung): rung is JournalVisibility =>
      JOURNAL_VISIBILITIES.includes(rung as JournalVisibility),
    ),
    date_from: day(params.date_from),
    date_to: day(params.date_to),
    q,
  };
}

/** A date range counts once, like the server's `active_count`. */
export function journalFilterCount(filter: JournalFeedFilter) {
  return [
    filter.kinds.length > 0,
    filter.sources.length > 0,
    filter.visibilities.length > 0,
    Boolean(filter.date_from || filter.date_to),
    Boolean(filter.q && filter.q.trim().length >= 2),
  ].filter(Boolean).length;
}

/** The filter the feed is asked for: text under 2 characters is not sent yet. */
export function effectiveJournalFilter(filter: JournalFeedFilter): JournalFeedFilter {
  const q = filter.q?.trim() ?? "";
  return {
    ...filter,
    kinds: [...filter.kinds].sort(),
    sources: [...filter.sources].sort(),
    visibilities: [...filter.visibilities].sort(),
    q: q.length >= 2 ? q : null,
  };
}

/** A stable cache key part for one filter. */
export function journalFilterKey(filter: JournalFeedFilter) {
  return JSON.stringify(effectiveJournalFilter(filter));
}

/** Drops sources that no longer exist (a provider removed from the account). */
export function withKnownSources(filter: JournalFeedFilter, known: Set<string>): JournalFeedFilter {
  const sources = filter.sources.filter((source) => known.has(source));
  return sources.length === filter.sources.length ? filter : { ...filter, sources };
}
