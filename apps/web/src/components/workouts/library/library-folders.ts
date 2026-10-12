import type { WorkoutFolder } from "@/api/workouts";
import type { WorkoutType } from "@/types/workout";

/** Folders the app maintains are recognised by their `system_key`, never by name. */
export type FolderKind = "athletes" | "athlete" | "classes" | "year" | "month" | "day" | "custom";

export const FOLDER_KIND_ICONS: Record<FolderKind, string> = {
  athletes: "👥",
  athlete: "🏃",
  classes: "🗓️",
  // Calendar emoji print a fixed date ("July 17") on most platforms, so date folders avoid them.
  year: "🗂️",
  month: "🗂️",
  day: "🗂️",
  custom: "📁",
};

const WORKOUT_TYPE_ICONS: Record<WorkoutType, string> = {
  crossfit: "🔥",
  strength: "🏋️",
  gymnastics: "🤸",
  aerobics: "🫀",
  flexibility: "🧘",
  recovery: "💆",
};

export function workoutIcon(type: string | null | undefined) {
  return WORKOUT_TYPE_ICONS[type as WorkoutType] ?? "🏋️";
}

export function folderKind(folder: Pick<WorkoutFolder, "system_key">): FolderKind {
  const key = folder.system_key ?? "";
  if (key === "athletes") return "athletes";
  if (key.startsWith("athlete:")) return "athlete";
  if (key === "classes") return "classes";
  if (/^classes:\d{4}$/.test(key)) return "year";
  if (/^classes:\d{4}-\d{2}$/.test(key)) return "month";
  if (/^classes:\d{4}-\d{2}-\d{2}$/.test(key)) return "day";
  return "custom";
}

/** The name the server gives a system folder; a different name means the coach renamed it. */
function defaultSystemName(folder: WorkoutFolder): string | null {
  const key = folder.system_key ?? "";
  switch (folderKind(folder)) {
    case "athletes":
      return "Athletes";
    case "classes":
      return "Classes";
    case "year":
      return key.slice(8, 12);
    case "month":
      return key.slice(13, 15);
    case "day":
      return key.slice(8);
    default:
      return null;
  }
}

export function folderDisplayName(
  folder: WorkoutFolder,
  labels: { athletes: string; classes: string },
  locale?: string,
) {
  if (defaultSystemName(folder) !== folder.name) return folder.name;
  const key = folder.system_key ?? "";

  switch (folderKind(folder)) {
    case "athletes":
      return labels.athletes;
    case "classes":
      return labels.classes;
    case "month": {
      const date = new Date(Date.UTC(Number(key.slice(8, 12)), Number(key.slice(13, 15)) - 1, 15));
      return capitalize(new Intl.DateTimeFormat(locale, { month: "long", timeZone: "UTC" }).format(date), locale);
    }
    case "day": {
      const date = new Date(`${key.slice(8)}T12:00:00Z`);
      return new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(date);
    }
    default:
      return folder.name;
  }
}

const ROOT_ORDER: Partial<Record<FolderKind, number>> = { athletes: 0, classes: 1 };

/** Athletes and Classes first, then natural name order (so "2" sorts before "10"). */
export function compareFolders(a: WorkoutFolder, b: WorkoutFolder) {
  const rank = (folder: WorkoutFolder) => ROOT_ORDER[folderKind(folder)] ?? 2;
  return rank(a) - rank(b) || a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
}

/** Month and day to draw on a class-day folder's calendar icon. */
export function dayFolderBadge(folder: WorkoutFolder, locale?: string) {
  if (folderKind(folder) !== "day") return null;
  const date = new Date(`${(folder.system_key ?? "").slice(8)}T12:00:00Z`);
  return {
    month: new Intl.DateTimeFormat(locale, { month: "short", timeZone: "UTC" }).format(date),
    day: String(date.getUTCDate()),
  };
}

/** Ids of `folderId` and every folder nested below it. */
export function folderSubtreeIds(folders: WorkoutFolder[], folderId: string) {
  const ids = new Set([folderId]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const folder of folders) {
      if (folder.parent_id && ids.has(folder.parent_id) && !ids.has(folder.id)) {
        ids.add(folder.id);
        grew = true;
      }
    }
  }
  return ids;
}

function capitalize(value: string, locale?: string) {
  return value.charAt(0).toLocaleUpperCase(locale) + value.slice(1);
}
