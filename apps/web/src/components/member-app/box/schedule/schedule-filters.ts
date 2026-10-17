import type { ClassAudience, ClassLevel, ScheduleSlot, WorkoutFocus } from "@/api/schedule";

/**
 * Box › Πρόγραμμα filters (plan §5a). Pure: the screen keeps the state, this
 * module decides what matches. Location is not a filter here; it sets the
 * screen's context (the title switch).
 */
export type SpotsFilter = "all" | "open" | "full_waitlist" | "full";
export type KindFilter = "all" | "class" | "event";
export type BookedFilter = "all" | "mine" | "mine_or_waitlist";
export type DurationBand = "short" | "medium" | "long";
export type TimeRange = { from: number; to: number };

export type ScheduleFilters = {
  classTypeIds: string[];
  kind: KindFilter;
  spots: SpotsFilter;
  packageOnly: boolean;
  levels: ClassLevel[];
  coachIds: string[];
  /** Minutes after local midnight; null means any time. */
  time: TimeRange | null;
  booked: BookedFilter;
  durations: DurationBand[];
  focus: WorkoutFocus[];
  audiences: ClassAudience[];
};

export const DEFAULT_SCHEDULE_FILTERS: ScheduleFilters = {
  classTypeIds: [],
  kind: "all",
  spots: "all",
  packageOnly: false,
  levels: [],
  coachIds: [],
  time: null,
  booked: "all",
  durations: [],
  focus: [],
  audiences: [],
};

/** The day the time range slider spans, in 30-minute steps. */
export const TIME_RANGE_BOUNDS: TimeRange = { from: 6 * 60, to: 23 * 60 };

export function durationBand(minutes: number): DurationBand {
  if (minutes <= 30) return "short";
  if (minutes <= 60) return "medium";
  return "long";
}

function localMinutes(iso: string) {
  const date = new Date(iso);
  return date.getHours() * 60 + date.getMinutes();
}

function isFull(slot: ScheduleSlot) {
  return slot.spots_remaining <= 0;
}

function bookingStatus(slot: ScheduleSlot) {
  return slot.current_user_booking?.status ?? null;
}

/** The member holds a place (or a pending request) in this class. */
export function isBookedByMe(slot: ScheduleSlot) {
  const status = bookingStatus(slot);
  return status === "approved" || status === "pending";
}

export function isWaitlistedByMe(slot: ScheduleSlot) {
  return bookingStatus(slot) === "waitlisted";
}

function intersects<T>(selected: T[], values: T[] | undefined) {
  return selected.length === 0 || (values ?? []).some((value) => selected.includes(value));
}

function matchesSpots(slot: ScheduleSlot, spots: SpotsFilter, now: Date) {
  switch (spots) {
    case "open":
      return !isFull(slot);
    case "full_waitlist":
      // Full classes you could still join the waitlist of.
      return isFull(slot) && new Date(slot.scheduled_at) > now && bookingStatus(slot) === null;
    case "full":
      return isFull(slot);
    default:
      return true;
  }
}

function matchesBooked(slot: ScheduleSlot, booked: BookedFilter) {
  if (booked === "mine") return isBookedByMe(slot);
  if (booked === "mine_or_waitlist") return isBookedByMe(slot) || isWaitlistedByMe(slot);
  return true;
}

function matchesTime(slot: ScheduleSlot, time: TimeRange | null) {
  if (!time) return true;
  const minutes = localMinutes(slot.scheduled_at);
  return minutes >= time.from && minutes <= time.to;
}

export function matchesScheduleFilters(slot: ScheduleSlot, filters: ScheduleFilters, now = new Date()) {
  const classType = slot.class_type;
  const kind = classType?.kind ?? "class";

  return (
    (filters.classTypeIds.length === 0 || filters.classTypeIds.includes(slot.class_type_id)) &&
    (filters.kind === "all" || filters.kind === kind) &&
    matchesSpots(slot, filters.spots, now) &&
    (!filters.packageOnly || slot.covered_by_package !== false) &&
    (filters.levels.length === 0 || filters.levels.includes(classType?.level ?? "all_levels")) &&
    (filters.coachIds.length === 0 || (slot.coach_user_id != null && filters.coachIds.includes(slot.coach_user_id))) &&
    matchesTime(slot, filters.time) &&
    matchesBooked(slot, filters.booked) &&
    (filters.durations.length === 0 || filters.durations.includes(durationBand(slot.duration_minutes))) &&
    intersects(filters.focus, slot.workout?.focus) &&
    intersects(filters.audiences, classType?.audiences)
  );
}

/** Classes at the chosen location; classes without a location belong to every one. */
export function atLocation(slot: ScheduleSlot, locationId: string | null) {
  return !locationId || !slot.location_id || slot.location_id === locationId;
}

/** How many filters are on: the n of «Φίλτρα (n)». */
export function activeFilterCount(filters: ScheduleFilters) {
  return [
    filters.classTypeIds.length > 0,
    filters.kind !== "all",
    filters.spots !== "all",
    filters.packageOnly,
    filters.levels.length > 0,
    filters.coachIds.length > 0,
    filters.time !== null,
    filters.booked !== "all",
    filters.durations.length > 0,
    filters.focus.length > 0,
    filters.audiences.length > 0,
  ].filter(Boolean).length;
}

const SPOTS: SpotsFilter[] = ["all", "open", "full_waitlist", "full"];
const KINDS: KindFilter[] = ["all", "class", "event"];
const BOOKED: BookedFilter[] = ["all", "mine", "mine_or_waitlist"];

function strings(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function pick<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

function subset<T extends string>(value: unknown, allowed: readonly T[]): T[] {
  return strings(value).filter((item): item is T => allowed.includes(item as T));
}

function timeRange(value: unknown): TimeRange | null {
  if (!value || typeof value !== "object") return null;
  const { from, to } = value as Record<string, unknown>;
  if (typeof from !== "number" || typeof to !== "number" || from > to) return null;
  return { from, to };
}

/** Reads remembered params defensively: unknown or stale values fall back to the defaults. */
export function parseScheduleFilters(
  value: unknown,
  vocab: { levels: readonly ClassLevel[]; audiences: readonly ClassAudience[]; focus: readonly WorkoutFocus[] },
): ScheduleFilters {
  if (!value || typeof value !== "object") return DEFAULT_SCHEDULE_FILTERS;
  const raw = value as Record<string, unknown>;

  return {
    classTypeIds: strings(raw.classTypeIds),
    kind: pick(raw.kind, KINDS, "all"),
    spots: pick(raw.spots, SPOTS, "all"),
    packageOnly: raw.packageOnly === true,
    levels: subset(raw.levels, vocab.levels),
    coachIds: strings(raw.coachIds),
    time: timeRange(raw.time),
    booked: pick(raw.booked, BOOKED, "all"),
    durations: subset(raw.durations, ["short", "medium", "long"] as const),
    focus: subset(raw.focus, vocab.focus),
    audiences: subset(raw.audiences, vocab.audiences),
  };
}

/** `locationId` null means «all locations»; absent means nothing chosen, so the home location applies. */
export type RememberedSchedule = { filters: ScheduleFilters; locationId?: string | null };
type RememberedByGym = Record<string, RememberedSchedule & { at: string }>;

/** Saved filters are account-wide, so the schedule keeps one entry per gym (newest few). */
export function rememberForGym(
  previous: unknown,
  organizationId: string,
  entry: RememberedSchedule,
  at = new Date().toISOString(),
  keep = 5,
): { gyms: RememberedByGym } {
  const gyms: RememberedByGym = {
    ...((previous as { gyms?: RememberedByGym } | null)?.gyms ?? {}),
    [organizationId]: { ...entry, at },
  };
  const newest = Object.entries(gyms)
    .sort(([, a], [, b]) => (a.at < b.at ? 1 : -1))
    .slice(0, keep);
  return { gyms: Object.fromEntries(newest) };
}

export function rememberedForGym(params: unknown, organizationId: string) {
  const entry = (params as { gyms?: Record<string, unknown> } | null)?.gyms?.[organizationId] as
    | { filters?: unknown; locationId?: unknown }
    | undefined;
  if (!entry) return undefined;
  const locationId =
    typeof entry.locationId === "string" ? entry.locationId : entry.locationId === null ? null : undefined;
  return { filters: entry.filters, locationId };
}

/** The first class starting after `after`, for the quiet «next match» line. */
export function nextMatch(slots: ScheduleSlot[], after: Date) {
  const time = (slot: ScheduleSlot) => new Date(slot.scheduled_at).getTime();
  return (
    slots.filter((slot) => time(slot) > after.getTime()).sort((a, b) => time(a) - time(b))[0] ?? null
  );
}

/** The two choices of the «Πακέτο» section on the filter page. */
export const PACKAGE_ONLY = "only";
export const PACKAGE_ALL = "all";
export type PackageChoice = typeof PACKAGE_ONLY | typeof PACKAGE_ALL;
