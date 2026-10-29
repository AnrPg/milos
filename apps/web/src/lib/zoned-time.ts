/**
 * ADR-179: one canonical clock, converted on demand.
 *
 * The API stores and sends every moment in UTC. A class or an event is
 * planned on its organiser's clock (the gym's zone, or an event's own zone
 * when it happens elsewhere), so that is the clock it is shown on. When the
 * viewer's device reads the moment differently (another offset at that
 * instant), the UI adds "your time" beside it.
 *
 * Pure helpers over IANA zone names and the platform's Intl; nothing here
 * touches React or the network.
 */

import { withClock } from "@/lib/clock";

export type ZonedFormat = "time" | "date-time" | "day" | "weekday-time" | "day-time";

const FORMATS: Record<ZonedFormat, Intl.DateTimeFormatOptions> = {
  time: { hour: "2-digit", minute: "2-digit" },
  "date-time": { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" },
  day: { weekday: "short", day: "numeric", month: "short" },
  "weekday-time": { weekday: "short", hour: "2-digit", minute: "2-digit" },
  "day-time": { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" },
};

const validity = new Map<string, boolean>();
const partFormatters = new Map<string, Intl.DateTimeFormat>();

/** This device's IANA zone, or null when the browser does not say. */
export function deviceTimeZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

/** An IANA zone this browser knows. */
export function isValidTimeZone(zone: string | null | undefined): zone is string {
  if (!zone) return false;
  const known = validity.get(zone);
  if (known !== undefined) return known;
  let valid = true;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    valid = false;
  }
  validity.set(zone, valid);
  return valid;
}

const UTC_ZONES = new Set(["UTC", "Etc/UTC", "Etc/GMT", "GMT", "Etc/Universal", "Zulu"]);

/** A short, locale-neutral name for a zone: its city ("Buenos Aires"), "UTC" for UTC. */
export function zoneLabel(zone: string | null | undefined): string {
  if (!zone || UTC_ZONES.has(zone)) return "UTC";
  const city = zone.split("/").pop() ?? zone;
  return city.replace(/_/g, " ");
}

function toDate(at: Date | string | number): Date {
  return at instanceof Date ? at : new Date(at);
}

function partsFormatter(zone: string) {
  let formatter = partFormatters.get(zone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    partFormatters.set(zone, formatter);
  }
  return formatter;
}

type WallClock = { year: number; month: number; day: number; hour: number; minute: number; second: number };

/** The zone's wall clock at a moment (the device's own when the zone is unknown). */
export function wallClock(at: Date | string | number, zone: string | null | undefined): WallClock {
  const date = toDate(at);
  if (!isValidTimeZone(zone)) {
    return {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes(),
      second: date.getSeconds(),
    };
  }
  const parts: Record<string, number> = {};
  for (const part of partsFormatter(zone).formatToParts(date)) {
    if (part.type !== "literal") parts[part.type] = Number(part.value);
  }
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour % 24,
    minute: parts.minute,
    second: parts.second,
  };
}

/** The zone's UTC offset at that moment, in minutes (DST included). */
export function offsetMinutes(at: Date | string | number, zone: string | null | undefined): number {
  const date = toDate(at);
  if (!isValidTimeZone(zone)) return -date.getTimezoneOffset();
  const clock = wallClock(date, zone);
  const asUtc = Date.UTC(clock.year, clock.month - 1, clock.day, clock.hour, clock.minute, clock.second);
  return Math.round((asUtc - Math.floor(date.getTime() / 1000) * 1000) / 60_000);
}

/** Both zones read the moment alike (same offset at that instant). */
export function sameClock(
  at: Date | string | number,
  zoneA: string | null | undefined,
  zoneB: string | null | undefined,
): boolean {
  if (zoneA === zoneB) return true;
  if (!isValidTimeZone(zoneA) || !isValidTimeZone(zoneB)) return false;
  return offsetMinutes(at, zoneA) === offsetMinutes(at, zoneB);
}

function pad(value: number) {
  return String(value).padStart(2, "0");
}

/** The calendar day ("YYYY-MM-DD") the moment falls on in the zone. */
export function dateKeyInZone(at: Date | string | number, zone: string | null | undefined): string {
  const clock = wallClock(at, zone);
  return `${clock.year}-${pad(clock.month)}-${pad(clock.day)}`;
}

/** "HH:MM" on the zone's clock. */
export function timeKeyInZone(at: Date | string | number, zone: string | null | undefined): string {
  const clock = wallClock(at, zone);
  return `${pad(clock.hour)}:${pad(clock.minute)}`;
}

/** "YYYY-MM-DDTHH:MM" on the zone's clock (a datetime-local input's value). */
export function dateTimeLocalInZone(at: Date | string | number, zone: string | null | undefined): string {
  return `${dateKeyInZone(at, zone)}T${timeKeyInZone(at, zone)}`;
}

/**
 * The moment a wall-clock time on a zone stands for. A time a DST jump skips
 * lands just after the jump; a repeated one takes the first.
 */
export function zonedToInstant(dateKey: string, time: string, zone: string | null | undefined): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  const [hour = 0, minute = 0] = time.split(":").map(Number);
  if (!isValidTimeZone(zone)) return new Date(year, month - 1, day, hour, minute, 0, 0);

  const asUtc = Date.UTC(year, month - 1, day, hour, minute, 0);
  const wanted = `${pad(hour)}:${pad(minute)}`;
  // The zone's offsets on either side of that day: a DST change falls
  // between them. Each gives one candidate moment.
  const candidates = Array.from(
    new Set([-86_400_000, 0, 86_400_000].map((shift) => asUtc - offsetMinutes(new Date(asUtc + shift), zone) * 60_000)),
  ).sort((a, b) => a - b);
  const fits = candidates.filter(
    (instant) => dateKeyInZone(new Date(instant), zone) === dateKey && timeKeyInZone(new Date(instant), zone) === wanted,
  );
  // A repeated hour: several fit, take the earlier moment. A skipped hour:
  // none fits, take the later one (just after the jump).
  const candidate = fits.length > 0 ? fits[0] : candidates[candidates.length - 1];
  return new Date(candidate);
}

/** The moment the zone's day begins. */
export function startOfDayInZone(dateKey: string, zone: string | null | undefined): Date {
  return zonedToInstant(dateKey, "00:00", zone);
}

/** The value of a datetime-local input, read on the zone's clock, as an ISO moment. */
export function dateTimeLocalToIso(value: string, zone: string | null | undefined): string {
  const [dateKey, time = "00:00"] = value.split("T");
  return zonedToInstant(dateKey, time.slice(0, 5), zone).toISOString();
}

/** The day after a "YYYY-MM-DD" key (calendar arithmetic, zone-free). */
export function addDaysToKey(dateKey: string, days: number): string {
  const [year, month, day] = dateKey.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

/** Text for a moment on a zone's clock (the device's own when the zone is unknown). */
export function formatInZone(
  at: Date | string | number,
  zone: string | null | undefined,
  locale: string,
  format: ZonedFormat | Intl.DateTimeFormatOptions = "time",
): string {
  const options = typeof format === "string" ? FORMATS[format] : format;
  const timeZone = isValidTimeZone(zone) ? zone : undefined;
  try {
    return new Intl.DateTimeFormat(locale, withClock(locale, { ...options, timeZone })).format(toDate(at));
  } catch {
    return new Intl.DateTimeFormat(undefined, withClock(locale, { ...options, timeZone })).format(toDate(at));
  }
}

export type ZonedReading = {
  /** On the organiser's clock. */
  text: string;
  /** The organiser's zone, as a city ("Athens"). */
  zone: string;
  /** On the viewer's clock when it reads the moment differently; else null. */
  local: string | null;
  /** The viewer's zone, as a city, when `local` is set. */
  localZone: string | null;
};

/**
 * A moment as a viewer reads it: on the organiser's clock, plus on their own
 * when it differs. The viewer's text repeats the day only when their day
 * differs and the format shows time only.
 */
export function readZoned(
  at: Date | string | number,
  organiserZone: string | null | undefined,
  viewerZone: string | null | undefined,
  locale: string,
  format: ZonedFormat = "time",
): ZonedReading {
  const text = formatInZone(at, organiserZone, locale, format);
  if (!isValidTimeZone(organiserZone) || !isValidTimeZone(viewerZone) || sameClock(at, organiserZone, viewerZone)) {
    return { text, zone: zoneLabel(organiserZone), local: null, localZone: null };
  }
  const otherDay = dateKeyInZone(at, organiserZone) !== dateKeyInZone(at, viewerZone);
  const localFormat: ZonedFormat = format === "time" && otherDay ? "weekday-time" : format;
  return {
    text,
    zone: zoneLabel(organiserZone),
    local: formatInZone(at, viewerZone, locale, localFormat),
    localZone: zoneLabel(viewerZone),
  };
}

/**
 * Compact text for lists: the organiser's clock, with its city added only
 * when the viewer's clock reads the moment differently ("19:00 Athens").
 * Detail views use the `ZonedTime` component, which also shows "your time".
 */
export function zonedText(
  at: Date | string | number,
  organiserZone: string | null | undefined,
  locale: string,
  format: ZonedFormat | Intl.DateTimeFormatOptions = "time",
  viewerZone: string | null | undefined = deviceTimeZone(),
): string {
  const text = formatInZone(at, organiserZone, locale, format);
  if (!isValidTimeZone(organiserZone) || !isValidTimeZone(viewerZone) || sameClock(at, organiserZone, viewerZone)) return text;
  return `${text} ${zoneLabel(organiserZone)}`;
}

/** Every IANA zone the browser knows, with the given ones kept even if it doesn't. */
export function timeZoneOptions(...always: Array<string | null | undefined>): string[] {
  let zones: string[] = [];
  try {
    zones = (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf?.("timeZone") ?? [];
  } catch {
    zones = [];
  }
  return Array.from(new Set([...always.filter((zone): zone is string => Boolean(zone)), ...zones])).sort();
}
