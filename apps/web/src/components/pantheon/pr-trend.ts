import type { PRHistoryEntry, PRRecord, PRSupportingMetrics } from "@/api/gamification";

/**
 * Πρόοδος › Personal Records trends (ADR-194, vision §7.7 Strength and
 * Benchmarks): from a PR's history, a lift's estimated 1RM over time and a
 * benchmark's score over time, the change over the chosen range, and a
 * «retest» hint when a benchmark has not been beaten for a while. Pure, so
 * every rule is unit tested; nothing compares the member with anyone.
 */

export type TrendKind = "strength" | "benchmark";
export type TrendPoint = { on: string; value: number };

export type PRTrend = {
  kind: TrendKind;
  /** Oldest first: the last score before the range (when there is one), then the range's. */
  points: TrendPoint[];
  latest: number;
  /** Signed improvement over the range in the PR's unit (positive is better), or null with one point. */
  improvement: number | null;
  /** A benchmark not beaten in RETEST_AFTER_DAYS: worth a retest. */
  retestDue: boolean;
};

/** Epley is unreliable past this many reps; such sets draw no 1RM point. */
export const MAX_ESTIMATE_REPS = 12;
/** A benchmark is worth retesting about every 12 weeks. */
export const RETEST_AFTER_DAYS = 84;

const DAY_MS = 86_400_000;

/** Estimated one-rep max (Epley): load × (1 + reps / 30); a single is the load itself. */
export function estimatedOneRepMax(load: number, reps = 1): number | null {
  if (!Number.isFinite(load) || load <= 0) return null;
  if (!Number.isFinite(reps) || reps < 1 || reps > MAX_ESTIMATE_REPS) return null;
  const value = reps === 1 ? load : load * (1 + reps / 30);
  return Math.round(value * 2) / 2;
}

function daysBetween(from: string, to: string) {
  return Math.round((Date.parse(`${to.slice(0, 10)}T00:00:00Z`) - Date.parse(`${from.slice(0, 10)}T00:00:00Z`)) / DAY_MS);
}

function pointValue(kind: TrendKind, score: number, metrics: PRSupportingMetrics | null | undefined) {
  if (!Number.isFinite(score)) return null;
  if (kind === "benchmark") return score;
  const reps = typeof metrics?.reps === "number" ? metrics.reps : 1;
  return estimatedOneRepMax(score, reps);
}

/**
 * The trend of one PR. `since` is the first day of the range (null for all
 * time); `today` an ISO day. Null when there is nothing to draw and no hint.
 */
export function prTrend(
  pr: Pick<PRRecord, "id" | "unit" | "higher_is_better" | "current_score" | "beaten_on" | "supporting_metrics">,
  history: Pick<PRHistoryEntry, "pr_record_id" | "score" | "beaten_on" | "supporting_metrics">[],
  { since, today }: { since: string | null; today: string },
): PRTrend | null {
  const kind: TrendKind = pr.unit === "kg" ? "strength" : "benchmark";
  const all = [
    ...history.filter((entry) => entry.pr_record_id === pr.id),
    { score: pr.current_score, beaten_on: pr.beaten_on, supporting_metrics: pr.supporting_metrics },
  ]
    .map((entry) => ({ on: entry.beaten_on.slice(0, 10), value: pointValue(kind, Number(entry.score), entry.supporting_metrics) }))
    .filter((point): point is TrendPoint => point.value !== null)
    .sort((left, right) => left.on.localeCompare(right.on));

  const retestDue = kind === "benchmark" && daysBetween(pr.beaten_on, today) >= RETEST_AFTER_DAYS;
  const inRange = since ? all.filter((point) => point.on >= since) : all;
  const before = since ? all.filter((point) => point.on < since).at(-1) : undefined;
  const points = before ? [before, ...inRange] : inRange;
  const latest = all.at(-1);

  if (!latest || (inRange.length === 0 && !retestDue)) return null;
  const change = points.length > 1 ? latest.value - points[0].value : null;
  return {
    kind,
    points,
    latest: latest.value,
    improvement: change === null || change === 0 ? change : pr.higher_is_better ? change : -change,
    retestDue,
  };
}

/**
 * Whether a PR passes Πρόοδος's source and exercise chips (ADR-194): a PR's
 * source is the gym it was set at, or `freeform` for a personal one; the
 * exercise matches its name, case and accents aside.
 */
export function prMatchesFilter(
  pr: Pick<PRRecord, "name" | "organization_id">,
  filter: { sources: string[]; exercise?: string | null },
): boolean {
  if (filter.sources.length > 0 && !filter.sources.includes(pr.organization_id ?? "freeform")) return false;
  const needle = fold(filter.exercise ?? "");
  return !needle || fold(pr.name).includes(needle);
}

function fold(text: string) {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase().trim();
}

/** SVG polyline points (oldest left), y flipped so better sits higher; null under two points. */
export function trendLine(points: TrendPoint[], higherIsBetter: boolean, width: number, height: number): string | null {
  if (points.length < 2) return null;
  const values = points.map((point) => (higherIsBetter ? point.value : -point.value));
  const min = Math.min(...values);
  const span = Math.max(...values) - min;
  const step = width / (points.length - 1);
  return values
    .map((value, index) => {
      const y = span === 0 ? height / 2 : height - ((value - min) / span) * height;
      return `${Math.round(index * step * 10) / 10},${Math.round(y * 10) / 10}`;
    })
    .join(" ");
}
