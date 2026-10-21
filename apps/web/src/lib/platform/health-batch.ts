// ADR-172: turns what the PaleeHealth plugin read from the phone into the
// API's ingest batches. Pure, so both platforms share one tested shaping:
//
//   - instants get the wearer's offset back (`2026-10-20T07:30:00+03:00`), so
//     the server knows the local day without a zone name;
//   - sleep segments (iOS) or sessions (Android) become one main sleep per
//     night, keyed by the local day it ends;
//   - a day's resting heart rate and steps travel together;
//   - lists are cut into batches of at most 500 records each.

export type HealthKind = "activities" | "sleep" | "weight" | "resting_hr" | "steps";

export const HEALTH_KINDS: HealthKind[] = ["activities", "sleep", "weight", "resting_hr", "steps"];

export type RawWorkout = {
  id: string;
  type?: string | null;
  title?: string | null;
  start: string;
  end: string;
  offset_minutes?: number | null;
  distance_m?: number | null;
  avg_hr?: number | null;
  max_hr?: number | null;
  source_app?: string | null;
};

export type RawSleep = {
  id: string;
  start: string;
  end: string;
  offset_minutes?: number | null;
  stage?: "asleep" | "in_bed" | "awake" | "session" | null;
};

export type RawWeight = { id: string; at: string; offset_minutes?: number | null; kg: number };

export type RawHealthRead = {
  workouts?: RawWorkout[];
  sleep?: RawSleep[];
  weights?: RawWeight[];
  resting_hr?: Array<{ date: string; bpm: number }>;
  steps?: Array<{ date: string; count: number }>;
};

export type IngestActivity = {
  id: string;
  type?: string;
  title?: string | null;
  start: string;
  end: string;
  distance_m?: number | null;
  avg_hr?: number | null;
  max_hr?: number | null;
  source_app?: string | null;
};
export type IngestSleep = { id: string; start: string; end: string };
export type IngestWeight = { id: string; at: string; kg: number };
export type IngestDaily = { date: string; resting_hr?: number | null; steps?: number | null };

export type IngestBatch = {
  activities?: IngestActivity[];
  sleeps?: IngestSleep[];
  weights?: IngestWeight[];
  dailies?: IngestDaily[];
};

export const MAX_PER_LIST = 500;

const MINUTE = 60_000;
// Segments closer than this belong to the same night (a wake-up at 4:00).
const NIGHT_GAP = 2 * 60 * MINUTE;
// Shorter spans are a doze on the sofa, not a night.
const MIN_SLEEP = 30 * MINUTE;

const pad = (value: number) => String(Math.abs(value)).padStart(2, "0");

/** `2026-10-20T04:30:00.000Z` with +180 minutes → `2026-10-20T07:30:00+03:00`. */
export function withOffset(iso: string, offsetMinutes: number | null | undefined): string | null {
  const at = Date.parse(iso);
  if (Number.isNaN(at)) return null;
  const offset = Number.isFinite(offsetMinutes) ? Math.round(offsetMinutes as number) : 0;
  const local = new Date(at + offset * MINUTE);
  const sign = offset < 0 ? "-" : "+";
  const date = `${local.getUTCFullYear()}-${pad(local.getUTCMonth() + 1)}-${pad(local.getUTCDate())}`;
  const time = `${pad(local.getUTCHours())}:${pad(local.getUTCMinutes())}:${pad(local.getUTCSeconds())}`;
  return `${date}T${time}${sign}${pad(Math.trunc(offset / 60))}:${pad(offset % 60)}`;
}

/** The wearer's calendar day at an instant. */
export function localDay(iso: string, offsetMinutes: number | null | undefined): string | null {
  const shifted = withOffset(iso, offsetMinutes);
  return shifted ? shifted.slice(0, 10) : null;
}

export function activities(workouts: RawWorkout[] = []): IngestActivity[] {
  const rows: IngestActivity[] = [];
  for (const workout of workouts) {
    const start = withOffset(workout.start, workout.offset_minutes);
    const end = withOffset(workout.end, workout.offset_minutes);
    if (!workout.id || !start || !end) continue;
    const row: IngestActivity = { id: workout.id, start, end };
    if (workout.type) row.type = workout.type;
    if (workout.title) row.title = workout.title;
    if (isNumber(workout.distance_m)) row.distance_m = workout.distance_m;
    if (isNumber(workout.avg_hr)) row.avg_hr = workout.avg_hr;
    if (isNumber(workout.max_hr)) row.max_hr = workout.max_hr;
    if (workout.source_app) row.source_app = workout.source_app;
    rows.push(row);
  }
  return rows;
}

type Span = { start: number; end: number; offset: number };

/**
 * One main sleep per night: asleep segments (or, when a night has none, time
 * in bed) close together are joined; the longest span ending on a local day
 * is that day's night, keyed by the day.
 */
export function nights(segments: RawSleep[] = []): IngestSleep[] {
  const usable = segments
    .map((segment) => ({ ...segment, startAt: Date.parse(segment.start), endAt: Date.parse(segment.end) }))
    .filter((segment) => !Number.isNaN(segment.startAt) && segment.endAt > segment.startAt && segment.stage !== "awake");
  const asleep = usable.filter((segment) => segment.stage !== "in_bed");
  const inBed = usable.filter((segment) => segment.stage === "in_bed");

  const spans = join(asleep);
  // Time in bed counts only for nights the phone saw no sleep in (older
  // iPhones without a watch record only that).
  for (const bed of join(inBed)) {
    if (!spans.some((span) => span.start < bed.end && bed.start < span.end)) spans.push(bed);
  }

  const byDay = new Map<string, Span>();
  for (const span of spans) {
    if (span.end - span.start < MIN_SLEEP) continue;
    const day = localDay(new Date(span.end).toISOString(), span.offset);
    if (!day) continue;
    const kept = byDay.get(day);
    if (!kept || span.end - span.start > kept.end - kept.start) byDay.set(day, span);
  }

  return [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, span]) => ({
      id: day,
      start: withOffset(new Date(span.start).toISOString(), span.offset)!,
      end: withOffset(new Date(span.end).toISOString(), span.offset)!,
    }));
}

function join(segments: Array<RawSleep & { startAt: number; endAt: number }>): Span[] {
  const sorted = [...segments].sort((a, b) => a.startAt - b.startAt);
  const spans: Span[] = [];
  for (const segment of sorted) {
    const last = spans[spans.length - 1];
    const offset = Number.isFinite(segment.offset_minutes) ? (segment.offset_minutes as number) : 0;
    if (last && segment.startAt - last.end <= NIGHT_GAP) {
      if (segment.endAt > last.end) {
        last.end = segment.endAt;
        last.offset = offset;
      }
    } else {
      spans.push({ start: segment.startAt, end: segment.endAt, offset });
    }
  }
  return spans;
}

export function weights(rows: RawWeight[] = []): IngestWeight[] {
  return rows.flatMap((row) => {
    const at = withOffset(row.at, row.offset_minutes);
    return row.id && at && isNumber(row.kg) ? [{ id: row.id, at, kg: Math.round(row.kg * 100) / 100 }] : [];
  });
}

/** A day's resting heart rate and steps in one record, oldest day first. */
export function dailies(read: Pick<RawHealthRead, "resting_hr" | "steps">): IngestDaily[] {
  const days = new Map<string, IngestDaily>();
  const day = (date: string) => {
    const found = days.get(date) ?? { date };
    days.set(date, found);
    return found;
  };
  for (const row of read.resting_hr ?? []) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(row.date) && isNumber(row.bpm)) day(row.date).resting_hr = Math.round(row.bpm);
  }
  for (const row of read.steps ?? []) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(row.date) && isNumber(row.count)) day(row.date).steps = Math.round(row.count);
  }
  return [...days.values()].sort((a, b) => a.date.localeCompare(b.date));
}

/** The whole read as API batches, none with more than 500 records in a list. */
export function toIngestBatches(read: RawHealthRead, max = MAX_PER_LIST): IngestBatch[] {
  const lists = {
    activities: activities(read.workouts),
    sleeps: nights(read.sleep),
    weights: weights(read.weights),
    dailies: dailies(read),
  };
  const count = Math.max(...Object.values(lists).map((list) => Math.ceil(list.length / max)));
  const batches: IngestBatch[] = [];
  for (let index = 0; index < count; index += 1) {
    const batch: IngestBatch = {};
    for (const [key, list] of Object.entries(lists) as Array<[keyof IngestBatch, unknown[]]>) {
      const slice = list.slice(index * max, (index + 1) * max);
      if (slice.length) (batch as Record<string, unknown[]>)[key] = slice;
    }
    batches.push(batch);
  }
  return batches;
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}
