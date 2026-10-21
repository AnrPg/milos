import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { WorkoutExecution } from "@/api/executions";
import type { PRRecord } from "@/api/gamification";
import type { ReviewRecord } from "@/api/reviews";
import type { TrainingLogEntry } from "@/api/training-log";
import type { CheckInRecord, InjuryRecord } from "@/api/wellbeing";
import type { Craving, MealPhoto, WellnessDay, WellnessEntry } from "@/api/wellness";

/**
 * Ημερολόγιο (ADR-139): the feed of every entry kind, moving an entry on the
 * visibility ladder, and Σημείωση notes.
 */
export type JournalFeedItem = components["schemas"]["JournalFeedItem"];
export type JournalFeedPage = components["schemas"]["JournalFeedPage"];
export type JournalKind = JournalFeedItem["kind"];
export type JournalVisibility = JournalFeedItem["journal_visibility"];
export type ChoosableVisibility = JournalFeedItem["choosable_visibilities"][number];
export type JournalVisibilityRequest = components["schemas"]["JournalVisibilityRequest"];
export type JournalVisibilityResult = components["schemas"]["JournalVisibilityResponse"];
export type JournalNote = components["schemas"]["JournalNote"];
export type JournalNoteTopic = JournalNote["topic"];
export type JournalNoteCreate = components["schemas"]["JournalNoteCreateRequest"];
export type JournalNoteUpdate = components["schemas"]["JournalNoteUpdateRequest"];

/** The entry inside an item, as its own endpoint returns it, by kind. */
export type JournalEntryOf = {
  execution: WorkoutExecution & { workout_title?: string | null; workout_type?: string | null };
  training_log: TrainingLogEntry;
  pr: PRRecord;
  injury: InjuryRecord;
  review: ReviewRecord;
  note: JournalNote;
  check_in: CheckInRecord;
  /** ADR-158: only ever in your own feed. */
  body: components["schemas"]["BodySnapshot"];
  /** ADR-159: a day of water, sleep and meals (the member's summary only in their own feed). */
  wellness: WellnessFeedDay;
  craving: Craving;
};

export type WellnessFeedDay = {
  id: string;
  date: string;
  organization_id: string | null;
  journal_visibility: JournalVisibility;
  summary: Omit<WellnessDay, "cravings" | "mood"> | null;
  entries: WellnessEntry[];
  photos: Record<string, MealPhoto>;
};

/** Kinds whose entries move on the ladder: feed kinds plus single wellness entries. */
export type JournalMoveKind = JournalKind | "wellness_entry";

export type TypedJournalItem = {
  [K in JournalKind]: Omit<JournalFeedItem, "kind" | "entry"> & { kind: K; entry: JournalEntryOf[K] };
}[JournalKind];

export const JOURNAL_FEED_KEY = ["my", "journal"] as const;

export const NOTE_TOPICS: JournalNoteTopic[] = ["technique", "thought", "mood", "goal"];

export function typedItem(item: JournalFeedItem): TypedJournalItem {
  return item as TypedJournalItem;
}

/**
 * Ημερολόγιο › Ροή filter (ADR-162 `JournalFilter`, version 1): Τύπος,
 * Πηγή (provider ids, `freeform`, `device`), Ορατότητα, dates and text. The
 * server echoes it in its canonical form and can remember it as the
 * member's last-used filter.
 */
export type JournalFeedFilter = {
  kinds: JournalKind[];
  sources: string[];
  visibilities: JournalVisibility[];
  date_from: string | null;
  date_to: string | null;
  q: string | null;
};

export const EMPTY_JOURNAL_FILTER: JournalFeedFilter = {
  kinds: [],
  sources: [],
  visibilities: [],
  date_from: null,
  date_to: null,
  q: null,
};

type PageParams = {
  cursor?: string | null;
  kinds?: JournalKind[] | null;
  limit?: number;
  filter?: Partial<JournalFeedFilter>;
  /** Also store the filter as the last-used Ημερολόγιο filter. */
  remember?: boolean;
};

function pageQuery(params: PageParams) {
  const query = new URLSearchParams();
  const filter = params.filter ?? {};
  if (params.cursor) query.set("cursor", params.cursor);
  if (params.kinds?.length) query.set("kinds", params.kinds.join(","));
  if (params.limit) query.set("limit", String(params.limit));
  if (filter.sources?.length) query.set("sources", filter.sources.join(","));
  if (filter.visibilities?.length) query.set("visibilities", filter.visibilities.join(","));
  if (filter.date_from) query.set("date_from", filter.date_from);
  if (filter.date_to) query.set("date_to", filter.date_to);
  if (filter.q?.trim()) query.set("q", filter.q.trim());
  if (params.remember) query.set("remember", "true");
  const text = query.toString();
  return text ? `?${text}` : "";
}

export function fetchJournalPage(token: string, params: PageParams = {}) {
  return apiRequest<JournalFeedPage>(`/me/journal${pageQuery(params)}`, { token });
}

export function fetchClientJournalPage(
  token: string,
  clientUserId: string,
  params: Pick<PageParams, "cursor" | "kinds" | "limit"> = {},
) {
  return apiRequest<JournalFeedPage>(`/staff/clients/${clientUserId}/journal${pageQuery(params)}`, { token });
}

export function setJournalVisibility(
  token: string,
  kind: JournalMoveKind,
  id: string,
  body: JournalVisibilityRequest,
) {
  return apiRequest<JournalVisibilityResult>(`/me/journal/entries/${kind}/${id}/visibility`, {
    method: "PUT",
    token,
    body,
  });
}

export async function createJournalNote(token: string, body: JournalNoteCreate) {
  const data = await apiRequest<{ note: JournalNote }>("/me/journal/notes", { method: "POST", token, body });
  return data.note;
}

export async function updateJournalNote(token: string, id: string, body: JournalNoteUpdate) {
  const data = await apiRequest<{ note: JournalNote }>(`/me/journal/notes/${id}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.note;
}

export function deleteJournalNote(token: string, id: string) {
  return apiRequest<void>(`/me/journal/notes/${id}`, { method: "DELETE", token });
}

/**
 * «Οι coach μου» across providers (ADR-162, board 17 Q5): which providers'
 * coaches the coach rungs reach by default, and one entry narrowed to some.
 */
export type CoachAudience = components["schemas"]["CoachAudience"];
export type EntryAudience = NonNullable<components["schemas"]["EntryAudience"]>;
export type AudienceKind = "execution" | "training_log" | "pr" | "note" | "check_in";
export const AUDIENCE_KINDS: readonly JournalKind[] = ["execution", "training_log", "pr", "note", "check_in"];
export const COACH_AUDIENCE_KEY = ["my", "journal", "coach-audience"] as const;

export function fetchCoachAudience(token: string) {
  return apiRequest<CoachAudience>("/me/journal/coach-audience", { token });
}

export function saveCoachAudience(token: string, organizationIds: string[]) {
  return apiRequest<CoachAudience>("/me/journal/coach-audience", {
    method: "PUT",
    token,
    body: { organization_ids: organizationIds },
  });
}

/** `null` puts the entry back on the default audience. */
export async function setEntryAudience(token: string, kind: AudienceKind, id: string, organizationIds: string[] | null) {
  const data = await apiRequest<components["schemas"]["EntryAudienceResponse"]>(
    `/me/journal/entries/${kind}/${id}/audience`,
    { method: "PUT", token, body: { organization_ids: organizationIds } },
  );
  return data.audience;
}

/** «Εξαγωγή» of the whole journal, every provider (board 17 Q6 extra). */
export type JournalExport = components["schemas"]["JournalExport"];
export const JOURNAL_EXPORTS_KEY = ["my", "journal", "exports"] as const;

export async function requestJournalExport(token: string) {
  const data = await apiRequest<components["schemas"]["JournalExportResponse"]>("/me/journal/export", {
    method: "POST",
    token,
  });
  return data.export as JournalExport;
}

export async function fetchJournalExports(token: string) {
  const data = await apiRequest<components["schemas"]["JournalExports"]>("/me/journal/exports", { token });
  return (data.exports ?? []) as JournalExport[];
}
