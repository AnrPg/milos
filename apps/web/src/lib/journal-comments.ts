import type {
  JournalComment,
  JournalCommentChange,
  JournalCommentDraft,
  JournalEntryKind,
} from "@/api/journal-comments";
import { newCommentId } from "@/api/journal-comments";

/**
 * Σχόλια (ADR-140 §1) are one list per entry wherever they were written:
 * during the workout, at the finish, in Καταγραφή or later. These helpers keep
 * a local list in step with what the server answers.
 */

function changeKey(comment: Pick<JournalComment, "change">): string | null {
  return comment.change?.patch_id ?? null;
}

/** Oldest first, as every surface lists them. */
export function sortComments(comments: JournalComment[]): JournalComment[] {
  return [...comments].sort(
    (a, b) => a.written_at.localeCompare(b.written_at) || a.id.localeCompare(b.id),
  );
}

/** The text of the most recent comment that has any, for a one-line preview. */
export function latestCommentBody(comments: JournalComment[] | undefined): string | null {
  const written = sortComments(comments ?? []).filter((comment) => comment.body?.trim());
  return written.at(-1)?.body ?? null;
}

/**
 * Puts a saved comment in the list: in place of the comment with its id, or
 * of the comment recording the same change (the server upserts changes by
 * patch id, so it may answer with an older comment's id).
 */
export function upsertComment(comments: JournalComment[], saved: JournalComment): JournalComment[] {
  const key = changeKey(saved);
  const rest = comments.filter(
    (comment) => comment.id !== saved.id && (key === null || changeKey(comment) !== key),
  );
  return sortComments([...rest, saved]);
}

export function removeComment(comments: JournalComment[], id: string): JournalComment[] {
  return comments.filter((comment) => comment.id !== id);
}

export function commentsForExercise(comments: JournalComment[], exerciseId: string): JournalComment[] {
  return comments.filter((comment) => comment.exercise_id === exerciseId);
}

/** Comments on the whole entry (no section, exercise or selection). */
export function entryLevelComments(comments: JournalComment[]): JournalComment[] {
  return comments.filter(
    (comment) => !comment.section_id && !comment.exercise_id && !comment.selected_text,
  );
}

export function changeComments(comments: JournalComment[]): JournalComment[] {
  return comments.filter((comment) => comment.change);
}

/** The change a comment records, as "prescribed → done". */
export function changeSummary(change: JournalCommentChange): string {
  const from = formatValue(change.canonical_value);
  const to = change.type === "skipped" ? "—" : formatValue(change.actual_value);
  const unit = change.unit ? ` ${change.unit}` : "";
  return `${from} → ${to}${unit}`;
}

function formatValue(value: JournalCommentChange["canonical_value"]): string {
  if (value === null || value === undefined || value === "") return "—";
  return String(value);
}

/**
 * An optimistic local copy of a draft, shown until the server answers (or
 * while the save waits in the offline outbox).
 */
export function localComment(draft: JournalCommentDraft, userId: string | null): JournalComment {
  return {
    ...draft,
    user_id: userId ?? undefined,
    tags: draft.tags ?? [],
    written_at: draft.written_at ?? new Date().toISOString(),
  };
}

export function commentDraft(
  entryKind: JournalEntryKind,
  entryId: string,
  fields: Omit<JournalCommentDraft, "id" | "entry_kind" | "entry_id"> & { id?: string },
): JournalCommentDraft {
  const { id, ...rest } = fields;
  return {
    id: id ?? newCommentId(),
    entry_kind: entryKind,
    entry_id: entryId,
    written_at: new Date().toISOString(),
    ...rest,
  };
}

/** A change patch carries its own text as `note`; on a comment it is the body. */
export function changeDraft(
  entryKind: JournalEntryKind,
  entryId: string,
  change: JournalCommentChange & { logged_at?: string },
  existing?: JournalComment,
): JournalCommentDraft {
  const { note, ...rest } = change;
  // `logged_at` dates the change in the journal; it is not part of the patch.
  const patch: Omit<typeof rest, "logged_at"> = { ...rest };
  delete (patch as { logged_at?: string }).logged_at;
  return commentDraft(entryKind, entryId, {
    id: existing?.id,
    body: note?.trim() ? note.trim() : (existing?.body ?? null),
    section_id: patch.section_id,
    exercise_id: patch.exercise_id ?? null,
    change: patch,
  });
}

/** What the finish step hands back: the changes as edited, and new text. */
export type FinishComments = {
  changes: Array<JournalCommentChange & { logged_at?: string }>;
  text: string | null;
};

/**
 * The comment writes a finish implies: each new or edited change (matched to
 * the comment already recording it by patch id), each removed change, and
 * the new text as a comment on the whole entry.
 */
export function finishWrites(
  entryKind: JournalEntryKind,
  entryId: string,
  existing: JournalComment[],
  finish: FinishComments,
): { save: JournalCommentDraft[]; remove: string[] } {
  const byKey = new Map(
    existing.filter((comment) => comment.change).map((comment) => [comment.change!.patch_id, comment]),
  );
  const keep = new Set<string>();
  const save: JournalCommentDraft[] = [];

  for (const change of finish.changes) {
    const current = byKey.get(change.patch_id);
    keep.add(change.patch_id);
    const unchanged =
      current?.change &&
      current.change.actual_value === change.actual_value &&
      current.change.type === change.type &&
      !change.note?.trim();
    if (!unchanged) save.push(changeDraft(entryKind, entryId, change, current));
  }

  // A change taken back is removed; text written with it stays as a comment.
  const remove: string[] = [];
  for (const [key, comment] of byKey) {
    if (keep.has(key)) continue;
    if (comment.body) {
      save.push({
        id: comment.id,
        entry_kind: comment.entry_kind,
        entry_id: comment.entry_id,
        section_id: comment.section_id,
        exercise_id: comment.exercise_id,
        tags: comment.tags,
        body: comment.body,
        change: null,
      });
    } else {
      remove.push(comment.id);
    }
  }

  if (finish.text?.trim()) {
    save.push(commentDraft(entryKind, entryId, { body: finish.text.trim() }));
  }

  return { save, remove };
}

type NamedExercise = { id?: string | null; name: string };
type SectionWithExercises = { exercises?: NamedExercise[] | null; sections?: SectionWithExercises[] | null };

/** Exercise names by id, for labelling comments anchored to an exercise. */
export function exerciseNamesOf(workout: { sections?: SectionWithExercises[] | null } | null | undefined) {
  const names: Record<string, string> = {};
  const walk = (sections: SectionWithExercises[] | null | undefined) => {
    for (const section of sections ?? []) {
      for (const exercise of section.exercises ?? []) if (exercise.id) names[exercise.id] = exercise.name;
      walk(section.sections);
    }
  };
  walk(workout?.sections);
  return names;
}
