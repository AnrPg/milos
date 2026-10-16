import type { ChoosableVisibility, JournalVisibility } from "@/api/journal";

/** Rungs in ladder order (ADR-139): the picker lists what an entry allows in this order. */
export const VISIBILITY_ORDER: JournalVisibility[] = [
  "private",
  "coach_can_view",
  "coach_reply_requested",
  "rated",
  "posted",
];

export function orderedChoices(choices: ChoosableVisibility[]): ChoosableVisibility[] {
  return VISIBILITY_ORDER.filter((rung): rung is ChoosableVisibility =>
    (choices as JournalVisibility[]).includes(rung),
  );
}

/** A reply request needs a question; every other rung is one tap. */
export function needsQuestion(rung: ChoosableVisibility): boolean {
  return rung === "coach_reply_requested";
}

/** The badge reads as the vision's icons: a lock, an eye, a speech bubble, a star, people. */
export const VISIBILITY_ICON: Record<JournalVisibility, string> = {
  private: "🔒",
  coach_can_view: "👁",
  coach_reply_requested: "💬",
  rated: "★",
  posted: "👥",
};
