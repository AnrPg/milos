import type { VoiceDraft } from "@/api/voice-log";
import { emptyTrainingLogForm, type TrainingLogForm } from "@/lib/training-log";

const DAY_MS = 24 * 60 * 60 * 1000;

function numberText(value: number | null | undefined): string {
  return typeof value === "number" && Number.isFinite(value) ? String(value) : "";
}

/**
 * ADR-175: the voice draft as a filled log form. The member reviews and
 * edits it; nothing here saves anything. A missing title falls back to
 * `fallbackTitle` (the form requires one for a freeform entry); notes go to
 * the entry's Σχόλιο; `days_ago` moves the time back by whole days.
 */
export function formFromVoiceDraft(
  draft: Partial<VoiceDraft> | null | undefined,
  now: Date,
  fallbackTitle: string,
): TrainingLogForm {
  const daysAgo = typeof draft?.days_ago === "number" && draft.days_ago > 0 ? Math.min(draft.days_ago, 14) : 0;
  const form = emptyTrainingLogForm(new Date(now.getTime() - daysAgo * DAY_MS), draft?.title?.trim() || fallbackTitle);

  return {
    ...form,
    durationMinutes: numberText(draft?.duration_minutes),
    perceivedEffort: numberText(draft?.perceived_effort),
    comment: draft?.notes?.trim() ?? "",
    exercises: (draft?.exercises ?? [])
      .filter((exercise) => exercise?.name?.trim())
      .map((exercise) => ({
        name: exercise.name.trim(),
        sets: numberText(exercise.sets),
        reps: numberText(exercise.reps),
        load: numberText(exercise.load),
        loadUnit: exercise.load_unit === "lb" ? "lb" : "kg",
      })),
  };
}
