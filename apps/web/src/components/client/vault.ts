import type { VaultEntry, VaultWorkout } from "@/api/executions";

/** One completed execution in the history list, with its workout (ADR-098). */
export type HistoryEntry = VaultEntry & {
  master_workout_id: string;
  workout_title: string | null;
  workout_type: string | null;
  /** ADR-167: the season the workout belonged to, when it was a season's. */
  season?: { id: string; title: string } | null;
  /** Calendar day the workout was completed on, `YYYY-MM-DD`. */
  day: string;
};

export type HistoryDay = { day: string; entries: HistoryEntry[] };

/**
 * Calendar day of a completion. The athlete's own timezone at completion time
 * wins, so a late-evening session stays on the day it was done; an unknown or
 * missing zone falls back to the viewer's zone (or `fallbackTimeZone`).
 */
export function entryDay(
  completedAtUtc: string,
  timeZone?: string | null,
  fallbackTimeZone?: string,
): string {
  const date = new Date(completedAtUtc);
  if (Number.isNaN(date.getTime())) return completedAtUtc.slice(0, 10);

  for (const zone of [timeZone, fallbackTimeZone]) {
    if (!zone) continue;
    try {
      return formatDay(date, zone);
    } catch {
      // Not a valid IANA zone; try the next one.
    }
  }
  return formatDay(date, undefined);
}

function formatDay(date: Date, timeZone: string | undefined) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

/** Every completed execution as its own entry, newest first; repeats stay separate. */
export function historyEntries(workouts: VaultWorkout[], fallbackTimeZone?: string): HistoryEntry[] {
  return workouts
    .flatMap((workout) =>
      workout.entries.map((entry) => ({
        ...entry,
        master_workout_id: workout.master_workout_id,
        workout_title: workout.workout_title ?? null,
        workout_type: workout.workout_type ?? null,
        day: entryDay(entry.completed_at_utc, entry.completed_at_tz, fallbackTimeZone),
      })),
    )
    .sort((a, b) => Date.parse(b.completed_at_utc) - Date.parse(a.completed_at_utc));
}

/** History entries grouped by completion day, keeping newest-first order. */
export function groupHistoryByDay(entries: HistoryEntry[]): HistoryDay[] {
  const days: HistoryDay[] = [];
  for (const entry of entries) {
    const last = days[days.length - 1];
    if (last && last.day === entry.day) {
      last.entries.push(entry);
    } else {
      days.push({ day: entry.day, entries: [entry] });
    }
  }
  return days;
}

/** Elapsed time as `m:ss` or `h:mm:ss`; null when nothing was timed. */
export function formatElapsed(ms: number | null | undefined): string | null {
  if (ms == null || !Number.isFinite(ms) || ms <= 0) return null;
  const totalSeconds = Math.round(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const ss = String(seconds).padStart(2, "0");
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${ss}`;
  return `${minutes}:${ss}`;
}

/** Case-insensitive title filter for the vault shelf. */
export function filterVault(workouts: VaultWorkout[], query: string): VaultWorkout[] {
  const needle = query.trim().toLocaleLowerCase();
  if (!needle) return workouts;
  return workouts.filter((workout) =>
    (workout.workout_title ?? "").toLocaleLowerCase().includes(needle),
  );
}

export type FinishedWorkout = {
  master_workout_id: string;
  title: string | null;
  type: string | null;
  /** Newest first. */
  entries: HistoryEntry[];
};
export type FinishedWorkoutFolder = { type: string | null; workouts: FinishedWorkout[] };

/**
 * The Journal's Workouts tab (ADR-103): every finished workout once, filed by
 * workout type, with each time it was done. Folders and workouts are ordered
 * by their latest completion.
 */
export function groupFinishedWorkouts(entries: HistoryEntry[]): FinishedWorkoutFolder[] {
  const byWorkout = new Map<string, FinishedWorkout>();
  for (const entry of entries) {
    const workout = byWorkout.get(entry.master_workout_id) ?? {
      master_workout_id: entry.master_workout_id,
      title: entry.workout_title,
      type: entry.workout_type,
      entries: [],
    };
    workout.entries.push(entry);
    byWorkout.set(entry.master_workout_id, workout);
  }
  const latest = (workout: FinishedWorkout) => workout.entries[0]?.completed_at_utc ?? "";
  const folders = new Map<string, FinishedWorkoutFolder>();
  for (const workout of byWorkout.values()) {
    workout.entries.sort((a, b) => (b.completed_at_utc ?? "").localeCompare(a.completed_at_utc ?? ""));
    const key = workout.type ?? "";
    const folder = folders.get(key) ?? { type: workout.type, workouts: [] };
    folder.workouts.push(workout);
    folders.set(key, folder);
  }
  const result = Array.from(folders.values());
  for (const folder of result) folder.workouts.sort((a, b) => latest(b).localeCompare(latest(a)));
  return result.sort((a, b) => latest(b.workouts[0]).localeCompare(latest(a.workouts[0])));
}
