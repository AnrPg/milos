import type {
  Craving,
  MealSlot,
  PortionKey,
  WellnessDay,
  WellnessEntry,
  WellnessItem,
  WellnessPlan,
  WellnessPreferences,
} from "@/api/wellness";
import { PORTION_KEYS, WELLNESS_ITEMS } from "@/api/wellness";

/**
 * Pure rules of the Ευεξία page (ADR-159, board 14): local days, the tile
 * order, glasses, the night from bedtime and wake time, meal slots, hand
 * portions against the plan and the week grid. Nothing here compares the
 * member with anyone, and nothing scores them.
 */

/** Past days can be filled in or corrected for up to this many days back. */
export const DAYS_BACK = 7;
export const DEFAULT_SLOTS: MealSlot[] = ["breakfast", "lunch", "dinner", "snack"];
const MAIN_SLOTS: MealSlot[] = ["breakfast", "lunch", "dinner"];

const pad = (value: number) => String(value).padStart(2, "0");

/** The local calendar date of `date` (YYYY-MM-DD). */
export function localDate(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day);
}

export function addDays(iso: string, days: number): string {
  const date = parseDate(iso);
  date.setDate(date.getDate() + days);
  return localDate(date);
}

export function daysBetween(from: string, to: string): number {
  return Math.round((parseDate(to).getTime() - parseDate(from).getTime()) / 86_400_000);
}

/** Whether `day` can still be filled in or corrected. */
export function editable(day: string, today: string): boolean {
  const back = daysBetween(day, today);
  return back >= 0 && back <= DAYS_BACK;
}

/** The Monday-to-Sunday week holding `day`, moved by `offset` weeks. */
export function weekOf(day: string, offset = 0): { from: string; to: string; dates: string[] } {
  const date = parseDate(day);
  const monday = addDays(day, -((date.getDay() + 6) % 7) + offset * 7);
  const dates = Array.from({ length: 7 }, (_, index) => addDays(monday, index));
  return { from: dates[0], to: dates[6], dates };
}

/** Every item once: the member's order first, items never placed after it. */
export function fullOrder(order: WellnessItem[]): WellnessItem[] {
  return [...order, ...WELLNESS_ITEMS].filter((item, index, all) => all.indexOf(item) === index);
}

/** The tiles in the member's order, without the ones they turned off. */
export function visibleItems(preferences: Pick<WellnessPreferences, "item_order" | "hidden_items">): WellnessItem[] {
  return fullOrder(preferences.item_order).filter((item) => !preferences.hidden_items.includes(item));
}

/** Moves `item` one place up (-1) or down (+1) in the full order. */
export function moveItem(order: WellnessItem[], item: WellnessItem, step: -1 | 1): WellnessItem[] {
  const full = fullOrder(order);
  const from = full.indexOf(item);
  const to = from + step;
  if (from < 0 || to < 0 || to >= full.length) return full;
  const next = [...full];
  [next[from], next[to]] = [next[to], next[from]];
  return next;
}

export function glasses(water: WellnessDay["water"]): { filled: number; goal: number } {
  return {
    filled: Math.round(water.ml / water.glass_ml),
    goal: Math.max(1, Math.ceil(water.goal_ml / water.glass_ml)),
  };
}

/** Minutes between bedtime and wake time ("HH:MM"), across midnight. */
export function sleepMinutes(bed: string, wake: string): number {
  const toMinutes = (time: string) => {
    const [hours, minutes] = time.split(":").map(Number);
    return hours * 60 + minutes;
  };
  const span = toMinutes(wake) - toMinutes(bed);
  return span <= 0 ? span + 1440 : span;
}

/**
 * The instants of a night that ends on the morning of `day`: the wake time
 * on `day`, the bedtime the evening before unless it is after midnight.
 */
export function nightInstants(day: string, bed: string, wake: string): { bed_at: string; wake_at: string } {
  const at = (iso: string, time: string) => {
    const [hours, minutes] = time.split(":").map(Number);
    const date = parseDate(iso);
    date.setHours(hours, minutes, 0, 0);
    return date.toISOString();
  };
  const bedDay = bed > wake ? addDays(day, -1) : day;
  return { bed_at: at(bedDay, bed), wake_at: at(day, wake) };
}

/** The usual bedtime and wake time, from the latest night that has both. */
export function usualNight(entries: WellnessEntry[]): { bed: string; wake: string } {
  const night = [...entries]
    .filter((entry) => entry.kind === "sleep" && !entry.value.nap && entry.value.bed_at && entry.value.wake_at)
    .sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))[0];
  if (!night) return { bed: "23:00", wake: "07:00" };
  const time = (iso: unknown) => {
    const date = new Date(String(iso));
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  };
  return { bed: time(night.value.bed_at), wake: time(night.value.wake_at) };
}

export function hoursAndMinutes(minutes: number): { hours: number; minutes: number } {
  return { hours: Math.floor(minutes / 60), minutes: minutes % 60 };
}

export function entriesOn(entries: WellnessEntry[], day: string, kind: WellnessEntry["kind"]) {
  return entries.filter((entry) => entry.occurred_on === day && entry.kind === kind);
}

/** The slots the meal sheet offers: the plan's, else the three plus a snack. */
export function mealSlots(plan: WellnessPlan | null | undefined): MealSlot[] {
  return plan?.meal_slots?.length ? plan.meal_slots : DEFAULT_SLOTS;
}

/** Each slot with the meals logged in it that day; snacks can repeat. */
export function mealsBySlot(meals: WellnessEntry[], slots: MealSlot[]) {
  const named = slots.map((slot) => ({ slot, meals: meals.filter((meal) => meal.value.slot === slot) }));
  const other = meals.filter((meal) => !slots.includes(meal.value.slot as MealSlot));
  return { named, other };
}

export function isMainSlot(slot: MealSlot) {
  return MAIN_SLOTS.includes(slot);
}

export type PortionBar = { key: PortionKey; logged: number; target: number; ratio: number };

/** Bars that fill as portions are logged, against the plan's daily portions. */
export function portionBars(
  logged: Record<string, number> | undefined,
  targets: WellnessPlan["portions"] | undefined,
): PortionBar[] {
  if (!targets) return [];
  return PORTION_KEYS.flatMap((key) => {
    const target = targets[key];
    if (!target) return [];
    const done = logged?.[key] ?? 0;
    return [{ key, logged: done, target, ratio: Math.min(1, done / target) }];
  });
}

export function stepPortion(value: number, step: 0.5 | -0.5): number {
  return Math.max(0, Math.min(10, Math.round((value + step) * 2) / 2));
}

export type Dot = "full" | "half" | "empty" | "warm";
export type WeekRow = "water" | "sleep" | "meals" | "cravings";

/** One dot per day and row: full on your own target, half when partly; cravings are a warm dot. */
export function weekDots(days: WellnessDay[], dates: string[]): Record<WeekRow, Dot[]> {
  const byDate = new Map(days.map((day) => [day.date, day]));
  const status = (value: "none" | "partial" | "full" | undefined): Dot =>
    value === "full" ? "full" : value === "partial" ? "half" : "empty";
  return {
    water: dates.map((date) => status(byDate.get(date)?.water.status)),
    sleep: dates.map((date) => status(byDate.get(date)?.sleep.status)),
    meals: dates.map((date) => status(byDate.get(date)?.meals.status)),
    cravings: dates.map((date) => ((byDate.get(date)?.cravings.count ?? 0) > 0 ? "warm" : "empty")),
  };
}

/** Rows of the week grid, without items the member turned off. */
export function weekRows(hidden: WellnessItem[]): WeekRow[] {
  const rows: WeekRow[] = ["water", "sleep", "meals", "cravings"];
  return rows.filter((row) => row === "cravings" || !hidden.includes(row));
}

export function cravingsOn(cravings: Craving[], day: string) {
  return cravings.filter((craving) => craving.occurred_on === day);
}

/** A craving still open: «Ακόμα την έχω» or no answer yet. */
export function openCraving(craving: Craving) {
  return !craving.outcome || craving.outcome === "ongoing";
}

/** An instant on `day` for back-filled entries: now's time of day, kept before now. */
export function occurredAt(day: string, now: Date): string | undefined {
  if (day === localDate(now)) return undefined;
  const date = parseDate(day);
  date.setHours(now.getHours(), now.getMinutes(), 0, 0);
  return date.toISOString();
}

const GRAMS_PER_PORTION: [PortionKey, "protein_grams" | "carbs_grams" | "fat_grams", number][] = [
  ["protein", "protein_grams", 25],
  ["carbs", "carbs_grams", 25],
  ["fat", "fat_grams", 10],
];

/** Daily hand portions from grams, as the API derives them (ADR-159): rounded to halves. */
export function portionsFromGrams(grams: Partial<Record<"protein_grams" | "carbs_grams" | "fat_grams", number | null>>) {
  return Object.fromEntries(
    GRAMS_PER_PORTION.flatMap(([key, field, per]) => {
      const value = grams[field];
      return typeof value === "number" && value > 0 ? [[key, Math.round((value / per) * 2) / 2]] : [];
    }),
  ) as Partial<Record<PortionKey, number>>;
}
