import type { PRHistoryEntry, PRRecord } from "@/api/gamification";

type PRHistoryDisplayEntry = Pick<PRHistoryEntry, "id" | "score" | "beaten_on" | "supporting_metrics" | "notes"> & {
  current: boolean;
};

export function chronologicalPRHistory(
  current: PRRecord,
  history: PRHistoryEntry[],
): PRHistoryDisplayEntry[] {
  return [
    {
      id: `current-${current.id}`,
      score: current.current_score,
      beaten_on: current.beaten_on,
      supporting_metrics: current.supporting_metrics,
      notes: current.notes,
      current: true,
    },
    ...history.map((entry) => ({ ...entry, current: false })),
  ].sort((left, right) => {
    const dateOrder = new Date(right.beaten_on).getTime() - new Date(left.beaten_on).getTime();
    return dateOrder || Number(right.current) - Number(left.current);
  });
}
