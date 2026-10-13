import type { WorkoutFolder, WorkoutRecord } from "@/api/workouts";
import type { WorkoutType } from "@/types/workout";

/** Folders the app maintains are recognised by their `system_key`, never by name. */
export type FolderKind =
  | "athletes"
  | "athlete"
  | "classes"
  | "year"
  | "month"
  | "day"
  | "memberVariations"
  | "memberVariation"
  | "custom";

export const FOLDER_KIND_ICONS: Record<FolderKind, string> = {
  athletes: "👥",
  athlete: "🏃",
  classes: "🗓️",
  // Calendar emoji print a fixed date ("July 17") on most platforms, so date folders avoid them.
  year: "🗂️",
  month: "🗂️",
  day: "🗂️",
  memberVariations: "🧬",
  memberVariation: "🙋",
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

/**
 * Keyword rules (English and Greek, accent-insensitive), checked in order; the
 * first match wins. They give files and coach-made folders a fitting icon with
 * no external service. A coach's own pick or an AI suggestion stored on the
 * workout takes precedence for files; folders always use these rules.
 */
const ICON_RULES: ReadonlyArray<readonly [string, RegExp]> = [
  ["💆", /deload|recover|regen|massage|spa\b|rest day|αποφορτ|αποκαταστ|ξεκουρ|μασαζ/],
  ["🧘", /mobility|yoga|stretch|flexib|breath|κινητικ|γιογκ|διατασ|ευλυγισ|αναπνο/],
  ["🎖️", /\bhero\b|murph|\bdt\b|ηρω/],
  ["🏆", /benchmark|\btest\b|\b1rm\b|\bmax\b|\bpr\b|\bfran\b|\bgrace\b|\bhelen\b|\bdiane\b|\bisabel\b|\bcindy\b|\bannie\b|\bkaren\b|\b2\d\.\d\b|τεστ|μεγιστ|αγων/],
  ["🤝", /partner|\bteam\b|\bpairs?\b|συνεργ|ζευγαρ|ομαδ/],
  ["🏃", /\brun|sprint|\b\d+k\b|jog|τρεξ|τρεχ|σπριντ/],
  ["🚣", /\brow|\berg\b|κωπηλ/],
  ["🚴", /bike|cycl|assault|echo|ποδηλ/],
  ["🏊", /swim|κολυμβ/],
  ["🤸", /gymnast|handstand|muscle.?up|pull.?up|\bskill|toes.?to.?bar|\brings?\b|γυμναστ|κατακορ|ασκησεις σωματος|μονοζυγ|κρικ/],
  ["⏱️", /\bemom\b|\bamrap\b|tabata|interval|\be\d+mom\b|διαλειμμ/],
  ["🫀", /cardio|engine|condition|aerobic|zone ?2|metcon|καρδι|αντοχ|αεροβι/],
  ["🦵", /\blegs?\b|lower body|ποδια|ποδιων|κατω ακρ/],
  ["💪", /upper body|\barms?\b|\bpush\b|\bpull\b|χερια|ανω ακρ/],
  ["🧱", /\bcore\b|\babs?\b|κορμο|κοιλιακ/],
  ["🏋️", /squat|deadlift|press|clean|snatch|jerk|strength|barbell|olympic|weightlift|καθισματ|αρση|ενδυναμ|δυναμ|μπαρα/],
  ["🔥", /burn|burpee|chipper|inferno|καψ|φωτι/],
];

function normalizeForRules(text: string) {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

/** The rule icon for a title or folder name, if any rule matches. */
export function ruleIcon(text: string | null | undefined) {
  if (!text) return null;
  const normalized = normalizeForRules(text);
  return ICON_RULES.find(([, pattern]) => pattern.test(normalized))?.[0] ?? null;
}

/** A workout's icon: the coach's or AI's stored choice, else keyword rules, else its type. */
export function resolveWorkoutIcon(workout: Pick<WorkoutRecord, "icon" | "title" | "type">) {
  return workout.icon || ruleIcon(workout.title) || workoutIcon(workout.type);
}

/** Folders use rules only: system folders by kind, coach folders by name. */
export function folderIcon(folder: WorkoutFolder) {
  const kind = folderKind(folder);
  if (kind !== "custom") return FOLDER_KIND_ICONS[kind];
  return ruleIcon(folder.name) ?? FOLDER_KIND_ICONS.custom;
}

/** Quick picks offered when a coach changes a workout's icon. */
export const ICON_CHOICES = [
  "🏋️", "🔥", "🫀", "🤸", "🧘", "💆", "🏃", "🚣", "🚴", "🏊", "⏱️", "🏆",
  "🎖️", "🤝", "🦵", "💪", "🧱", "⚡", "🥵", "🧠", "🎯", "🧊", "🌅", "🎉",
];

export function folderKind(folder: Pick<WorkoutFolder, "system_key">): FolderKind {
  const key = folder.system_key ?? "";
  if (key === "athletes") return "athletes";
  if (key.startsWith("athlete:")) return "athlete";
  if (key === "classes") return "classes";
  if (key === "member_variations") return "memberVariations";
  if (key.startsWith("member_variations:")) return "memberVariation";
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
    case "memberVariations":
      return "Variations for member";
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
  labels: { athletes: string; classes: string; memberVariations?: string },
  locale?: string,
) {
  if (defaultSystemName(folder) !== folder.name) return folder.name;
  const key = folder.system_key ?? "";

  switch (folderKind(folder)) {
    case "athletes":
      return labels.athletes;
    case "classes":
      return labels.classes;
    case "memberVariations":
      return labels.memberVariations ?? folder.name;
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

const ROOT_ORDER: Partial<Record<FolderKind, number>> = { athletes: 0, classes: 1, memberVariations: 2 };

/** Athletes, Classes and Variations for member first, then natural name order (so "2" sorts before "10"). */
export function compareFolders(a: WorkoutFolder, b: WorkoutFolder) {
  const rank = (folder: WorkoutFolder) => ROOT_ORDER[folderKind(folder)] ?? 3;
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
