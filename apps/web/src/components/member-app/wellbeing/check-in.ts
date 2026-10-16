import type { CheckInRecord } from "@/api/wellbeing";

/** Answers run from 1 (worst) to 4 (best); there is no neutral middle (ADR-140 §2). */
export const CHECK_IN_VALUES = [1, 2, 3, 4] as const;
export type CheckInValue = (typeof CHECK_IN_VALUES)[number];

export const CHECK_IN_FACES: Record<CheckInValue, string> = { 1: "😣", 2: "😕", 3: "🙂", 4: "😄" };

export type CheckInDraft = Record<string, { value: CheckInValue; note: string }>;

/** Tapping an answer selects it; tapping the selected answer clears the question. */
export function toggleAnswer(draft: CheckInDraft, key: string, value: CheckInValue): CheckInDraft {
  if (draft[key]?.value === value) {
    return Object.fromEntries(Object.entries(draft).filter(([entryKey]) => entryKey !== key));
  }
  return { ...draft, [key]: { value, note: draft[key]?.note ?? "" } };
}

/** The request body for a draft, in catalog order; blank notes are omitted. */
export function draftAnswers(draft: CheckInDraft, questionKeys: string[]) {
  return questionKeys
    .filter((key) => draft[key])
    .map((key) => {
      const note = draft[key].note.trim();
      return { question_key: key, value: draft[key].value, ...(note ? { note } : {}) };
    });
}

export type TimelinePoint = { id: string; at: string; value: number; note: string | null; x: number; y: number };

/**
 * One question's line: a point per submission that answered it, placed by
 * time in [from, to] (x in 0..1) and by value (y in 0..1, 1 = best).
 */
export function questionTimeline(checkIns: CheckInRecord[], key: string, from: Date, to: Date): TimelinePoint[] {
  const span = Math.max(1, to.getTime() - from.getTime());

  return checkIns.flatMap((checkIn) => {
    const answer = checkIn.answers.find((entry) => entry.question_key === key);
    if (!answer) return [];
    const at = new Date(checkIn.recorded_at).getTime();
    return [
      {
        id: checkIn.id,
        at: checkIn.recorded_at,
        value: answer.value,
        note: answer.note ?? null,
        x: Math.min(1, Math.max(0, (at - from.getTime()) / span)),
        y: (answer.value - 1) / 3,
      },
    ];
  });
}

/** The latest answer to each question: the member's current state. */
export function latestAnswers(checkIns: CheckInRecord[]) {
  const latest: Record<string, { value: number; at: string }> = {};
  for (const checkIn of checkIns) {
    for (const answer of checkIn.answers) {
      const current = latest[answer.question_key];
      if (!current || current.at < checkIn.recorded_at) {
        latest[answer.question_key] = { value: answer.value, at: checkIn.recorded_at };
      }
    }
  }
  return latest;
}

export function timelineWindow(now: Date, days: number) {
  const to = new Date(now.getTime() + 60_000);
  const from = new Date(now.getTime() - days * 86_400_000);
  return { from, to };
}
