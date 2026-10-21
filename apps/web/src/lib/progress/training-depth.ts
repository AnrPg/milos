/**
 * Pure helpers for the Πρόοδος depth sections (ADR-165): the qualities radar
 * geometry, the load chart scale and safe reads of the API payload. Every
 * reader tolerates missing fields (e2e catch-all stubs answer `{}`).
 */

export const QUALITY_IDS = [
  "cardiorespiratory-endurance",
  "stamina",
  "strength",
  "flexibility",
  "power",
  "speed",
  "coordination",
  "agility",
  "balance",
  "accuracy",
] as const;
export type QualityId = (typeof QUALITY_IDS)[number];

export const LOAD_BANDS = ["below", "steady", "above", "well_above"] as const;
export type LoadBand = (typeof LOAD_BANDS)[number];

export type QualityRow = { id: string; sets?: number; score?: number; felt?: number };

function finite(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/** The ten qualities in canonical order, each with a 0..1 score (missing = 0). */
export function qualityScores(rows: readonly QualityRow[] | null | undefined): Array<{ id: QualityId; score: number; sets: number; felt: number }> {
  const byId = new Map((rows ?? []).filter((row) => row && typeof row.id === "string").map((row) => [row.id, row]));
  return QUALITY_IDS.map((id) => {
    const row = byId.get(id);
    return {
      id,
      score: Math.min(1, Math.max(0, finite(row?.score))),
      sets: finite(row?.sets),
      felt: finite(row?.felt),
    };
  });
}

/** Point of axis `index` of `count` at `radius` (0..1) around `center`, first axis straight up. */
export function radarPoint(index: number, count: number, radius: number, center: number, size: number): [number, number] {
  const angle = (Math.PI * 2 * index) / count - Math.PI / 2;
  return [center + Math.cos(angle) * radius * size, center + Math.sin(angle) * radius * size];
}

/** SVG `points` of a polygon with one radius per axis. */
export function radarPolygon(radii: readonly number[], center: number, size: number): string {
  return radii
    .map((radius, index) => radarPoint(index, radii.length, radius, center, size))
    .map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`)
    .join(" ");
}

/** The `count` most-trained (or most-felt) qualities with anything at all. */
export function topQualities(rows: ReturnType<typeof qualityScores>, key: "sets" | "felt", count: number): QualityId[] {
  return rows
    .filter((row) => row[key] > 0)
    .sort((a, b) => b[key] - a[key])
    .slice(0, count)
    .map((row) => row.id);
}

export type LoadWeek = { week_start: string; load?: number; sessions?: number };

/** Bars of the load chart: each week's share (0..100) of the largest week. */
export function loadBars(weeks: readonly LoadWeek[] | null | undefined): Array<{ week_start: string; load: number; percent: number }> {
  const rows = (weeks ?? []).filter((week) => week && typeof week.week_start === "string");
  const top = Math.max(0, ...rows.map((week) => finite(week.load)));
  return rows.map((week) => ({
    week_start: week.week_start,
    load: finite(week.load),
    percent: top > 0 ? Math.round((finite(week.load) / top) * 100) : 0,
  }));
}

export function isLoadBand(value: unknown): value is LoadBand {
  return typeof value === "string" && (LOAD_BANDS as readonly string[]).includes(value);
}

/** A ratio such as 1.4 as «1,4 : 1» in the locale; null when there is none. */
export function formatRatio(ratio: number | null | undefined, locale: string): string | null {
  if (typeof ratio !== "number" || !Number.isFinite(ratio) || ratio <= 0) return null;
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1, minimumFractionDigits: 1 }).format(ratio)} : 1`;
}
