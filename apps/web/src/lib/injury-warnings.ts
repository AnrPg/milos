import type {
  AthleteInjuryWarningEntry,
  InjuryWarning,
  InjuryWarningLevel,
} from "@/api/injury-warnings";

// Pure helpers for ADR-114 injury warning UI. Warnings inform; nothing here
// is ever used to disable an action.

const LEVEL_RANK: Record<InjuryWarningLevel, number> = { none: 0, caution: 1, avoid: 2 };

export function maxWarningLevel(levels: InjuryWarningLevel[]): InjuryWarningLevel {
  return levels.reduce<InjuryWarningLevel>(
    (highest, level) => (LEVEL_RANK[level] > LEVEL_RANK[highest] ? level : highest),
    "none",
  );
}

/** Athletes that actually carry a warning, most severe first, then by name. */
export function warnedAthletes(
  athletes: AthleteInjuryWarningEntry[],
  nameFor: (userId: string) => string,
): Array<AthleteInjuryWarningEntry & { name: string }> {
  return athletes
    .filter((athlete) => athlete.level !== "none" && athlete.warnings.length > 0)
    .map((athlete) => ({ ...athlete, name: nameFor(athlete.user_id) }))
    .sort(
      (left, right) =>
        LEVEL_RANK[right.level] - LEVEL_RANK[left.level] || left.name.localeCompare(right.name),
    );
}

/** user_id -> level for badge rendering (only warned users are present). */
export function warningLevelsByUser(athletes: AthleteInjuryWarningEntry[]): Map<string, InjuryWarningLevel> {
  return new Map(
    athletes
      .filter((athlete) => athlete.level !== "none")
      .map((athlete) => [athlete.user_id, athlete.level] as const),
  );
}

/** A user's level from `warningLevelsByUser`, `none` when unwarned. */
export function warningLevelFor(levels: Map<string, InjuryWarningLevel>, userId: string): InjuryWarningLevel {
  return levels.get(userId) ?? "none";
}

/** Exercise names a warning touches, grouped by level, de-duplicated, avoid first. */
export function affectedExercises(warning: InjuryWarning): { avoid: string[]; caution: string[] } {
  const avoid = new Set<string>();
  const caution = new Set<string>();

  for (const exercise of warning.exercises) {
    (exercise.level === "avoid" ? avoid : caution).add(exercise.name);
  }

  for (const name of avoid) caution.delete(name);
  return { avoid: [...avoid], caution: [...caution] };
}

/** Stable key so a selection change triggers exactly one re-evaluation. */
export function selectionKey(userIds: string[]): string {
  return [...new Set(userIds)].sort().join(",");
}
