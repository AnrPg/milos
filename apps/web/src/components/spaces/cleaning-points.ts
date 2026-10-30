// ADR-290: the janitor's answers to a room's visual cleaning checklist.

export type PointStatus = "cleaned" | "not_cleaned";

export type PointAnswer = {
  status?: PointStatus;
  note?: string;
  afterMediaId?: string | null;
  afterPreview?: string | null;
};

export type PointResultInput = {
  point_id: string;
  status: PointStatus;
  note: string | null;
  after_media_id: string | null;
};

/** Whether a point's answer can be sent: a status, and a note when not cleaned. */
export function answerReady(answer: PointAnswer | undefined): boolean {
  if (!answer?.status) return false;
  return answer.status === "cleaned" || Boolean(answer.note?.trim());
}

/** The index of the first point still needing an answer, or -1 when all are ready. */
export function firstUnanswered(points: { id: string }[], answers: Record<string, PointAnswer>): number {
  return points.findIndex((point) => !answerReady(answers[point.id]));
}

/** The answers as the API takes them, in the points' order. */
export function toPointResults(points: { id: string }[], answers: Record<string, PointAnswer>): PointResultInput[] {
  return points.map((point) => {
    const answer = answers[point.id] ?? {};
    return {
      point_id: point.id,
      status: answer.status ?? "cleaned",
      note: answer.note?.trim() || null,
      after_media_id: answer.afterMediaId ?? null,
    };
  });
}

/** How many points of a finished cleaning were cleaned, and how many not. */
export function resultCounts(results: { status: string }[] | null | undefined) {
  const list = results ?? [];
  const cleaned = list.filter((result) => result.status === "cleaned").length;
  return { cleaned, notCleaned: list.length - cleaned };
}
