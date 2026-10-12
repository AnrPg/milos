import type { SectionScore } from "@/api/executions";

/** The parts of progress an athlete changes by hand, which survive a version conflict. */
export type ProgressMarks = {
  checkedExerciseIds: string[];
  segmentCycleCounts: Record<string, number>;
  sectionScores: SectionScore[];
  /** Mid-workout clock changes in seconds, by segment key. */
  durationAdjustments?: Record<string, number>;
};

/**
 * Replays local, unacknowledged marks on top of a newer server version.
 *
 * `base` is the last server state this device saw, `local` is what the
 * athlete did since, and `server` is what another device (or tab) saved in
 * the meantime. Check-offs added or removed locally are re-applied, round
 * counts and clock adjustments keep their local delta, and scores entered locally replace the
 * server's for the same section. Everything else (clock, position, pause)
 * follows the server, because the other device's timeline is authoritative.
 */
export function rebaseProgressMarks(
  base: ProgressMarks,
  local: ProgressMarks,
  server: ProgressMarks,
): ProgressMarks {
  const baseChecked = new Set(base.checkedExerciseIds);
  const localChecked = new Set(local.checkedExerciseIds);
  const checked = new Set(server.checkedExerciseIds);
  for (const id of local.checkedExerciseIds) if (!baseChecked.has(id)) checked.add(id);
  for (const id of base.checkedExerciseIds) if (!localChecked.has(id)) checked.delete(id);

  const segmentCycleCounts = replayDeltas(base.segmentCycleCounts, local.segmentCycleCounts, server.segmentCycleCounts, 0);
  const durationAdjustments = replayDeltas(
    base.durationAdjustments ?? {},
    local.durationAdjustments ?? {},
    server.durationAdjustments ?? {},
    null,
  );

  const baseScores = new Map(base.sectionScores.map((score) => [score.section_id, JSON.stringify(score)]));
  const sectionScores = [...server.sectionScores];
  for (const score of local.sectionScores) {
    if (baseScores.get(score.section_id) === JSON.stringify(score)) continue;
    const index = sectionScores.findIndex((candidate) => candidate.section_id === score.section_id);
    if (index >= 0) sectionScores[index] = score;
    else sectionScores.push(score);
  }

  return { checkedExerciseIds: [...checked], segmentCycleCounts, sectionScores, durationAdjustments };
}

/** Adds each key's local change (local − base) to the server value; `floor` clamps, null allows negatives. */
function replayDeltas(
  base: Record<string, number>,
  local: Record<string, number>,
  server: Record<string, number>,
  floor: number | null,
) {
  const result = { ...server };
  for (const key of new Set([...Object.keys(base), ...Object.keys(local)])) {
    const delta = (local[key] ?? 0) - (base[key] ?? 0);
    if (delta === 0) continue;
    const next = (result[key] ?? 0) + delta;
    result[key] = floor === null ? next : Math.max(floor, next);
    if (floor === null && result[key] === 0) delete result[key];
  }
  return result;
}

export function hasMarkChanges(base: ProgressMarks, local: ProgressMarks): boolean {
  return JSON.stringify(normalize(base)) !== JSON.stringify(normalize(local));
}

function normalize(marks: ProgressMarks) {
  return {
    checked: [...marks.checkedExerciseIds].sort(),
    cycles: Object.entries(marks.segmentCycleCounts)
      .filter(([, value]) => value !== 0)
      .sort(([a], [b]) => a.localeCompare(b)),
    scores: [...marks.sectionScores]
      .sort((a, b) => a.section_id.localeCompare(b.section_id))
      .map((score) => JSON.stringify(score)),
    clock: Object.entries(marks.durationAdjustments ?? {})
      .filter(([, value]) => value !== 0)
      .sort(([a], [b]) => a.localeCompare(b)),
  };
}
