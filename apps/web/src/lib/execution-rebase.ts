import type { SectionScore } from "@/api/executions";

/** The parts of progress an athlete changes by hand, which survive a version conflict. */
export type ProgressMarks = {
  checkedExerciseIds: string[];
  segmentCycleCounts: Record<string, number>;
  sectionScores: SectionScore[];
};

/**
 * Replays local, unacknowledged marks on top of a newer server version.
 *
 * `base` is the last server state this device saw, `local` is what the
 * athlete did since, and `server` is what another device (or tab) saved in
 * the meantime. Check-offs added or removed locally are re-applied, round
 * counts keep their local delta, and scores entered locally replace the
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

  const segmentCycleCounts = { ...server.segmentCycleCounts };
  const keys = new Set([...Object.keys(base.segmentCycleCounts), ...Object.keys(local.segmentCycleCounts)]);
  for (const key of keys) {
    const delta = (local.segmentCycleCounts[key] ?? 0) - (base.segmentCycleCounts[key] ?? 0);
    if (delta !== 0) segmentCycleCounts[key] = Math.max(0, (segmentCycleCounts[key] ?? 0) + delta);
  }

  const baseScores = new Map(base.sectionScores.map((score) => [score.section_id, JSON.stringify(score)]));
  const sectionScores = [...server.sectionScores];
  for (const score of local.sectionScores) {
    if (baseScores.get(score.section_id) === JSON.stringify(score)) continue;
    const index = sectionScores.findIndex((candidate) => candidate.section_id === score.section_id);
    if (index >= 0) sectionScores[index] = score;
    else sectionScores.push(score);
  }

  return { checkedExerciseIds: [...checked], segmentCycleCounts, sectionScores };
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
  };
}
