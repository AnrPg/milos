import type {
  BoxScreenClass,
  BoxScreenLeaderboard,
  BoxScreenPairing,
  BoxScreenToday,
  BoxScreenWorkout,
} from "@/api/box-screens";
import { addDaysToKey, dateKeyInZone, zonedToInstant } from "@/lib/zoned-time";

// ADR-253, mockup s8 option A: the box screen follows the class by itself
// (before: WOD and bookings; during: the timer; after: the leaderboard) and
// staff can pin one view until they return it to automatic. Pure, so it is
// unit-tested; the TV page only renders what `screenScene` says.

const RESULTS_MINUTES = 30;

/** What the TV shows right now. */
export type ScreenScene =
  | { kind: "preview"; slot: BoxScreenClass; workout: BoxScreenWorkout | null }
  | { kind: "timer"; slot: BoxScreenClass; workout: BoxScreenWorkout | null; leaderboard: BoxScreenLeaderboard | null }
  | { kind: "results"; slot: BoxScreenClass | null; workout: BoxScreenWorkout | null; leaderboard: BoxScreenLeaderboard | null }
  | { kind: "wod"; slot: BoxScreenClass | null; workout: BoxScreenWorkout }
  | { kind: "leaderboard"; slot: BoxScreenClass | null; workout: BoxScreenWorkout; leaderboard: BoxScreenLeaderboard | null }
  | { kind: "bookings"; slot: BoxScreenClass }
  | { kind: "idle" };

const at = (iso: string) => Date.parse(iso);

function live(today: BoxScreenToday) {
  return today.classes.filter((slot) => !slot.cancelled).sort((a, b) => at(a.scheduled_at) - at(b.scheduled_at));
}

function running(today: BoxScreenToday, now: number) {
  return live(today).find((slot) => at(slot.scheduled_at) <= now && now < at(slot.ends_at)) ?? null;
}

function upcoming(today: BoxScreenToday, now: number) {
  return live(today).find((slot) => at(slot.scheduled_at) > now) ?? null;
}

function lastEnded(today: BoxScreenToday, now: number) {
  return [...live(today)].reverse().find((slot) => at(slot.ends_at) <= now) ?? null;
}

export function workoutOf(today: BoxScreenToday, slot: BoxScreenClass | null) {
  if (!slot?.workout_id) return null;
  return today.workouts.find((workout) => workout.id === slot.workout_id) ?? null;
}

export function leaderboardOf(today: BoxScreenToday, workout: BoxScreenWorkout | null) {
  if (!workout) return null;
  return today.leaderboards.find((board) => board.workout_id === workout.id) ?? null;
}

function phaseOfClass(today: BoxScreenToday, slot: BoxScreenClass, now: number): ScreenScene {
  const workout = workoutOf(today, slot);
  if (now < at(slot.scheduled_at)) return { kind: "preview", slot, workout };
  if (now < at(slot.ends_at)) return { kind: "timer", slot, workout, leaderboard: leaderboardOf(today, workout) };
  return { kind: "results", slot, workout, leaderboard: leaderboardOf(today, workout) };
}

/** The scene for the focus the API chose (automatic or pinned by staff). */
export function screenScene(today: BoxScreenToday, now: number): ScreenScene {
  const { focus } = today;
  const named = focus.slot_id ? today.classes.find((slot) => slot.id === focus.slot_id) ?? null : null;
  const current = named ?? running(today, now) ?? upcoming(today, now) ?? lastEnded(today, now);
  // A pinned WOD or leaderboard without a class of its own: today's first WOD.
  const workoutForPin = workoutOf(today, current) ?? today.workouts[0] ?? null;

  switch (focus.view) {
    case "preview": {
      const slot = named ?? upcoming(today, now);
      return slot ? { kind: "preview", slot, workout: workoutOf(today, slot) } : { kind: "idle" };
    }
    case "timer": {
      const slot = named ?? running(today, now) ?? upcoming(today, now);
      if (!slot) return { kind: "idle" };
      const workout = workoutOf(today, slot);
      return { kind: "timer", slot, workout, leaderboard: leaderboardOf(today, workout) };
    }
    case "results": {
      const slot = named ?? lastEnded(today, now);
      const workout = workoutOf(today, slot) ?? (slot ? null : workoutForPin);
      return { kind: "results", slot, workout, leaderboard: leaderboardOf(today, workout) };
    }
    case "wod":
      return workoutForPin ? { kind: "wod", slot: current, workout: workoutForPin } : { kind: "idle" };
    case "leaderboard":
      return workoutForPin
        ? { kind: "leaderboard", slot: current, workout: workoutForPin, leaderboard: leaderboardOf(today, workoutForPin) }
        : { kind: "idle" };
    case "bookings":
      return current ? { kind: "bookings", slot: current } : { kind: "idle" };
    case "class":
      return named ? phaseOfClass(today, named, now) : { kind: "idle" };
    default:
      return { kind: "idle" };
  }
}

/**
 * When the automatic focus can change next (a class starts or ends, its
 * results window closes, a pin runs out): the TV reads /today again then.
 */
export function nextChangeAt(today: BoxScreenToday, now: number): number | null {
  const moments = live(today).flatMap((slot) => [
    at(slot.scheduled_at),
    at(slot.ends_at),
    at(slot.ends_at) + RESULTS_MINUTES * 60_000,
  ]);
  if (today.focus.until) moments.push(at(today.focus.until));
  const future = moments.filter((moment) => Number.isFinite(moment) && moment > now);
  return future.length > 0 ? Math.min(...future) : null;
}

/** Whole minutes until a class starts, never below zero. */
export function minutesUntil(iso: string, now: number) {
  return Math.max(0, Math.ceil((at(iso) - now) / 60_000));
}

/** "Rx", "Scaled", "Αρχάριοι": a scale level slug as people read it. */
export function scaleLabel(slug: string | null | undefined) {
  if (!slug) return null;
  if (slug.toLowerCase() === "rx") return "Rx";
  const words = slug.replace(/[-_]+/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function scoreText(entry: { value: string | null; unit: string | null }) {
  return [entry.value, entry.unit].filter(Boolean).join(" ");
}

/** Keys of leaderboard rows that were not there before (a score just came in). */
export function newEntryKeys(
  previous: BoxScreenLeaderboard["entries"] | null,
  next: BoxScreenLeaderboard["entries"],
): string[] {
  if (!previous) return [];
  const before = new Set(previous.map(entryKey));
  return next.map(entryKey).filter((key) => !before.has(key));
}

export function entryKey(entry: { name: string; value: string | null }) {
  return `${entry.name}|${entry.value ?? ""}`;
}

// --- Pairing -----------------------------------------------------------------

const CODE_LENGTH = 8;

/** What the person typed, as the 8 symbols of a code: case, spaces and dashes do not matter. */
export function normalizePairingCode(input: string) {
  return input
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, CODE_LENGTH);
}

/** "ABCD-EFGH", also while it is being typed ("ABCD-E"). */
export function formatPairingCode(input: string) {
  const code = normalizePairingCode(input);
  return code.length > 4 ? `${code.slice(0, 4)}-${code.slice(4)}` : code;
}

export function pairingCodeComplete(input: string) {
  return normalizePairingCode(input).length === CODE_LENGTH;
}

const STORAGE_KEY = "palee:box-screen";

/** The TV's own pairing, kept on the device (it is not a person's session). */
export function readStoredPairing(): BoxScreenPairing | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<BoxScreenPairing>;
    if (typeof parsed.token !== "string" || !parsed.box?.id || !parsed.screen?.id) return null;
    return parsed as BoxScreenPairing;
  } catch {
    return null;
  }
}

export function storePairing(pairing: BoxScreenPairing | null) {
  try {
    if (pairing) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(pairing));
    else window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Private mode: the TV pairs again after a reload.
  }
}

const RENEW_WITHIN_MS = 60 * 86_400_000;

/** The 90-day display token is renewed once it has less than 60 days left. */
export function tokenNeedsRenewal(expiresAt: string, now: number) {
  const expires = at(expiresAt);
  return !Number.isFinite(expires) || expires - now < RENEW_WITHIN_MS;
}

// --- Staff override ----------------------------------------------------------

/**
 * «Έως» as an ISO moment: the next time the box's clock shows `time`
 * (today, or tomorrow when it has passed), so it is always within 24 hours.
 */
export function untilFromTime(time: string, zone: string | null, now: number) {
  const today = dateKeyInZone(now, zone);
  const candidate = zonedToInstant(today, time, zone);
  const moment = candidate.getTime() > now ? candidate : zonedToInstant(addDaysToKey(today, 1), time, zone);
  return moment.toISOString();
}

/** Today's classes a screen shows: its branch's and the whole box's (every class for a whole-box screen). */
export function classesOnScreen<T extends { location_id?: string | null; cancelled_at?: string | null }>(
  slots: T[],
  screenLocationId: string | null,
) {
  return slots.filter(
    (slot) =>
      !slot.cancelled_at &&
      (screenLocationId === null || !slot.location_id || slot.location_id === screenLocationId),
  );
}
