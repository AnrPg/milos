import type { ApproveScalingRequest, ScalingSuggestionItem } from "@/api/scaling";

/** The coach's edits on one suggestion: unticked changes and rewritten suggestions, by item id. */
export type ScalingReviewDraft = {
  excluded: Record<string, boolean>;
  suggested: Record<string, string>;
  dropScale: boolean;
  note: string;
};

export const emptyDraft = (): ScalingReviewDraft => ({ excluded: {}, suggested: {}, dropScale: false, note: "" });

/** How many changes would be approved; with no change and no scale level there is nothing to approve. */
export function approvableCount(items: ScalingSuggestionItem[], scale: string | null | undefined, draft: ScalingReviewDraft) {
  const kept = items.filter((item) => !draft.excluded[item.id]).length;
  return kept + (scale && !draft.dropScale ? 1 : 0);
}

/** The approve request: only what the coach changed is sent; everything else is approved as proposed. */
export function approveBody(items: ScalingSuggestionItem[], draft: ScalingReviewDraft): ApproveScalingRequest {
  type Review = { id: string; include?: boolean; suggested?: string };
  const reviews = items.flatMap((item): Review[] => {
    if (draft.excluded[item.id]) return [{ id: item.id, include: false }];
    const edited = draft.suggested[item.id]?.trim();
    if (edited && edited !== (item.suggested ?? "")) return [{ id: item.id, suggested: edited.slice(0, 120) }];
    return [];
  });
  const body: ApproveScalingRequest = {};
  if (reviews.length > 0) body.items = reviews;
  if (draft.dropScale) body.scale_level_slug = null;
  const note = draft.note.trim();
  if (note) body.coach_note = note.slice(0, 500);
  return body;
}
