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
  /** ADR-161: a watch workout that matched nothing (always the owner's). */
  device_activity: components["schemas"]["DeviceActivity"];
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

export type JournalFilter = "all" | "training" | "notes" | "wellbeing";

/** The kinds each Ροή filter chip lists. */
export const JOURNAL_FILTER_KINDS: Record<JournalFilter, JournalKind[] | null> = {
  all: null,
  training: ["execution", "training_log", "pr"],
  notes: ["note"],
  wellbeing: ["check_in", "injury", "wellness", "craving"],
};

export function typedItem(item: JournalFeedItem): TypedJournalItem {
  return item as TypedJournalItem;
}

function pageQuery(params: { cursor?: string | null; kinds?: JournalKind[] | null; limit?: number }) {
  const query = new URLSearchParams();
  if (params.cursor) query.set("cursor", params.cursor);
  if (params.kinds?.length) query.set("kinds", params.kinds.join(","));
  if (params.limit) query.set("limit", String(params.limit));
  const text = query.toString();
  return text ? `?${text}` : "";
}

export function fetchJournalPage(
  token: string,
  params: { cursor?: string | null; kinds?: JournalKind[] | null; limit?: number } = {},
) {
  return apiRequest<JournalFeedPage>(`/me/journal${pageQuery(params)}`, { token });
}

export function fetchClientJournalPage(
  token: string,
  clientUserId: string,
  params: { cursor?: string | null; kinds?: JournalKind[] | null; limit?: number } = {},
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
