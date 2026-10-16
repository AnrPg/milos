import type {
  CreateTrainingLogRequest,
  PerformedExercise,
  TrainingLogEntry,
  TrainingLogScoreableSection,
  TrainingLogSourceType,
  UpdateTrainingLogRequest,
} from "@/api/training-log";
import { newCommentId, type JournalCommentDraft } from "@/api/journal-comments";
import { commentDraft } from "@/lib/journal-comments";

export type LoadUnit = "kg" | "lb";

export type TrainingLogExerciseRow = {
  name: string;
  sets: string;
  reps: string;
  load: string;
  loadUnit: LoadUnit;
};

export type TrainingLogForm = {
  title: string;
  performedAt: string;
  durationMinutes: string;
  perceivedEffort: string;
  /** A Σχόλιο written with the entry (ADR-140 §1); its id keeps replays converging. */
  comment: string;
  commentId: string;
  sectionScores: Record<string, string>;
  exercises: TrainingLogExerciseRow[];
};

export type SelectedTrainingSource = {
  sourceType: TrainingLogSourceType;
  referenceId: string | null;
  title: string;
  scoreableSections: TrainingLogScoreableSection[];
};

export type TrainingLogFormError =
  | "titleRequired"
  | "performedAtRequired"
  | "performedAtFuture"
  | "durationInvalid"
  | "exerciseNameRequired"
  | "exerciseNumberInvalid";

const FUTURE_TOLERANCE_MS = 15 * 60 * 1000;
const MAX_DURATION_MINUTES = 24 * 60;

function pad(value: number) {
  return String(value).padStart(2, "0");
}

/** Formats a date for an `<input type="datetime-local">` in the viewer's local time. */
export function toDateTimeLocal(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function fromDateTimeLocal(value: string): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function emptyExerciseRow(): TrainingLogExerciseRow {
  return { name: "", sets: "", reps: "", load: "", loadUnit: "kg" };
}

export function emptyTrainingLogForm(now: Date, title = ""): TrainingLogForm {
  return {
    title,
    performedAt: toDateTimeLocal(now),
    durationMinutes: "",
    perceivedEffort: "",
    comment: "",
    commentId: newCommentId(),
    sectionScores: {},
    exercises: [],
  };
}

function isBlank(value: string) {
  return value.trim() === "";
}

function parseNonNegativeInt(value: string): number | null | "invalid" {
  if (isBlank(value)) return null;
  if (!/^\d+$/.test(value.trim())) return "invalid";
  return Number.parseInt(value.trim(), 10);
}

function parseNonNegativeNumber(value: string): number | null | "invalid" {
  if (isBlank(value)) return null;
  const parsed = Number(value.trim().replace(",", "."));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : "invalid";
}

export function validateTrainingLogForm(
  form: TrainingLogForm,
  sourceType: TrainingLogSourceType,
  now: Date,
): TrainingLogFormError[] {
  const errors: TrainingLogFormError[] = [];

  if (sourceType === "freeform" && isBlank(form.title)) errors.push("titleRequired");

  const performedAt = fromDateTimeLocal(form.performedAt);
  if (!performedAt) errors.push("performedAtRequired");
  else if (performedAt.getTime() - now.getTime() > FUTURE_TOLERANCE_MS) errors.push("performedAtFuture");

  const minutes = parseNonNegativeInt(form.durationMinutes);
  if (minutes === "invalid" || (typeof minutes === "number" && minutes > MAX_DURATION_MINUTES)) {
    errors.push("durationInvalid");
  }

  const filledRows = form.exercises.filter((row) => !isRowEmpty(row));
  if (filledRows.some((row) => isBlank(row.name))) errors.push("exerciseNameRequired");
  if (
    filledRows.some(
      (row) =>
        parseNonNegativeInt(row.sets) === "invalid" ||
        parseNonNegativeInt(row.reps) === "invalid" ||
        parseNonNegativeNumber(row.load) === "invalid",
    )
  ) {
    errors.push("exerciseNumberInvalid");
  }

  return errors;
}

function isRowEmpty(row: TrainingLogExerciseRow) {
  return isBlank(row.name) && isBlank(row.sets) && isBlank(row.reps) && isBlank(row.load);
}

function exercisesPayload(rows: TrainingLogExerciseRow[]): PerformedExercise[] {
  return rows
    .filter((row) => !isRowEmpty(row))
    .map((row) => {
      const exercise: PerformedExercise = { name: row.name.trim() };
      const sets = parseNonNegativeInt(row.sets);
      const reps = parseNonNegativeInt(row.reps);
      const load = parseNonNegativeNumber(row.load);
      if (typeof sets === "number" && sets > 0) exercise.sets = sets;
      if (typeof reps === "number") exercise.reps = reps;
      if (typeof load === "number") {
        exercise.load = load;
        exercise.load_unit = row.loadUnit;
      }
      return exercise;
    });
}

function scoresPayload(form: TrainingLogForm, sections: TrainingLogScoreableSection[]) {
  return sections.flatMap((section) => {
    const raw = form.sectionScores[section.id]?.trim();
    if (!raw) return [];
    const numeric = Number(raw.replace(",", "."));
    return [
      {
        section_id: section.id,
        value: Number.isFinite(numeric) && /^[\d.,]+$/.test(raw) ? numeric : raw,
        unit: section.unit ?? null,
      },
    ];
  });
}

function detailsPayload(
  form: TrainingLogForm,
  sections: TrainingLogScoreableSection[],
  timezone: string,
) {
  const performedAt = fromDateTimeLocal(form.performedAt);
  const minutes = parseNonNegativeInt(form.durationMinutes);
  const effort = parseNonNegativeInt(form.perceivedEffort);

  return {
    performed_at: (performedAt ?? new Date()).toISOString(),
    timezone,
    duration_seconds: typeof minutes === "number" ? minutes * 60 : null,
    perceived_effort: typeof effort === "number" && effort >= 1 && effort <= 10 ? effort : null,
    section_scores: scoresPayload(form, sections),
    performed_exercises: exercisesPayload(form.exercises),
  };
}

export function buildCreatePayload(
  form: TrainingLogForm,
  source: SelectedTrainingSource,
  options: { idempotencyKey: string; timezone: string },
): CreateTrainingLogRequest {
  return {
    ...detailsPayload(form, source.scoreableSections, options.timezone),
    source_type: source.sourceType,
    source_reference_id: source.sourceType === "freeform" ? null : source.referenceId,
    title: source.sourceType === "freeform" ? form.title.trim() : null,
    idempotency_key: options.idempotencyKey,
    comments: isBlank(form.comment) ? [] : [{ id: form.commentId, body: form.comment.trim() }],
  };
}

/** On an existing entry the comment is saved on its own, after the edit. */
export function commentDraftFromForm(form: TrainingLogForm, entryId: string): JournalCommentDraft | null {
  if (isBlank(form.comment)) return null;
  return commentDraft("training_log", entryId, { id: form.commentId, body: form.comment.trim() });
}

export function buildUpdatePayload(
  form: TrainingLogForm,
  entry: TrainingLogEntry,
  sections: TrainingLogScoreableSection[],
  timezone: string,
): UpdateTrainingLogRequest {
  const payload: UpdateTrainingLogRequest = {
    ...detailsPayload(form, sections, timezone),
    expected_version: entry.lock_version,
  };

  if (entry.source_type === "freeform") payload.title = form.title.trim();
  // Scores are only editable when the form offers their sections.
  if (sections.length === 0) delete payload.section_scores;

  return payload;
}

export function formFromEntry(entry: TrainingLogEntry): TrainingLogForm {
  return {
    title: entry.title,
    performedAt: toDateTimeLocal(new Date(entry.performed_at_utc)),
    durationMinutes:
      typeof entry.duration_seconds === "number" ? String(Math.round(entry.duration_seconds / 60)) : "",
    perceivedEffort: typeof entry.perceived_effort === "number" ? String(entry.perceived_effort) : "",
    comment: "",
    commentId: newCommentId(),
    sectionScores: Object.fromEntries(
      entry.section_scores.map((score) => [score.section_id, String(score.value)]),
    ),
    exercises: entry.performed_exercises.map((exercise) => ({
      name: exercise.name,
      sets: exercise.sets == null ? "" : String(exercise.sets),
      reps: exercise.reps == null ? "" : String(exercise.reps),
      load: exercise.load == null ? "" : String(exercise.load),
      loadUnit: exercise.load_unit === "lb" ? "lb" : "kg",
    })),
  };
}

/** Synthetic sections for editing a sourced entry whose scores were logged before. */
export function sectionsFromEntryScores(entry: TrainingLogEntry): TrainingLogScoreableSection[] {
  return entry.section_scores.map((score) => ({
    id: score.section_id,
    name: null,
    score_type: null,
    unit: score.unit ?? null,
  }));
}

export function newIdempotencyKey(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return `log-${crypto.randomUUID()}`;
  return `log-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

export function sortEntriesNewestFirst(entries: TrainingLogEntry[]): TrainingLogEntry[] {
  return [...entries].sort(
    (left, right) =>
      new Date(right.performed_at_utc).getTime() - new Date(left.performed_at_utc).getTime(),
  );
}
