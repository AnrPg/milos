import type { DayWorkout } from "@/api/day-workouts";
import type { ClassTypeRecord, ScheduleSlot } from "@/api/schedule";
import { dateKeyInZone } from "@/lib/zoned-time";

/**
 * ADR-230: reading the day WODs of the schedule. The server decides which
 * rule a class follows; these helpers mirror its order for display only:
 * a class type beats «all», a branch beats «all branches», and an
 * all-classes rule never covers events.
 */

/** The day's rules, all-classes first, then by class type name. */
export function dayWorkoutsOn(rules: DayWorkout[] | undefined, date: string, classTypes: ClassTypeRecord[] = []): DayWorkout[] {
  const name = (rule: DayWorkout) => classTypes.find((type) => type.id === rule.class_type_id)?.name ?? "";
  return (rules ?? [])
    .filter((rule) => rule.local_date === date)
    .sort((a, b) => specificity(a) - specificity(b) || name(a).localeCompare(name(b)));
}

export function specificity(rule: Pick<DayWorkout, "class_type_id" | "location_id">) {
  return (rule.class_type_id ? 2 : 0) + (rule.location_id ? 1 : 0);
}

function covers(rule: DayWorkout, slot: ScheduleSlot) {
  const typeMatches = rule.class_type_id
    ? rule.class_type_id === slot.class_type_id
    : (slot.class_type?.kind ?? "class") === "class";
  const locationMatches = !rule.location_id || rule.location_id === (slot.location_id ?? null);
  return typeMatches && locationMatches;
}

/** The day WOD that covers a class, on the gym's clock; null when none does. */
export function coveringDayWorkout(rules: DayWorkout[] | undefined, slot: ScheduleSlot, zone: string | null): DayWorkout | null {
  const date = dateKeyInZone(slot.scheduled_at, zone);
  return (
    (rules ?? [])
      .filter((rule) => rule.local_date === date && covers(rule, slot))
      .sort((a, b) => specificity(b) - specificity(a))[0] ?? null
  );
}

/** The classes of the day that took their WOD from this rule. */
export function inheritedFrom(rule: DayWorkout, slots: ScheduleSlot[]) {
  return slots.filter((slot) => slot.day_workout_id === rule.id);
}

/** What a rule covers, in words: «Όλα τα μαθήματα», «CrossFit», «CrossFit · Βόρειο». */
export function dayWorkoutScope(
  rule: Pick<DayWorkout, "class_type_id" | "location_id">,
  names: { allClasses: string; classType: (id: string) => string | undefined; location: (id: string) => string | undefined },
) {
  const type = rule.class_type_id ? names.classType(rule.class_type_id) ?? names.allClasses : names.allClasses;
  const branch = rule.location_id ? names.location(rule.location_id) : null;
  return branch ? `${type} · ${branch}` : type;
}


/** «Τρ 3 Νοε»: a gym date as people read it (the date itself has no zone). */
export function dayLabel(date: string, locale: string) {
  const [year, month, day] = date.split("-").map(Number);
  return new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(
    new Date(Date.UTC(year, month - 1, day, 12)),
  );
}
