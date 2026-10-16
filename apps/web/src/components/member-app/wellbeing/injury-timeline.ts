export type InjuryChange = { field: string; from: unknown; to: unknown };

export type InjuryEvent = {
  id: string;
  event_type: "reported" | "updated" | "marked_healed" | "reopened";
  actor_id: string | null;
  occurred_at: string;
  payload: { note?: string | null; changes?: InjuryChange[]; [key: string]: unknown };
};

/**
 * Where each event sits on the injury's line, 0..1 from the first event to
 * the last, so the gaps show how the injury progressed over time.
 */
export function timelinePositions(events: Pick<InjuryEvent, "occurred_at">[]): number[] {
  if (events.length === 0) return [];
  const times = events.map((event) => new Date(event.occurred_at).getTime());
  const first = Math.min(...times);
  const span = Math.max(...times) - first;
  if (span === 0) return times.map((_time, index) => (events.length === 1 ? 0 : index / (events.length - 1)));
  return times.map((time) => (time - first) / span);
}
