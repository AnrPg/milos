import type {
  BodyCatalogEntry,
  BodyDelta,
  BodyMetric,
  BodyMetrics,
  BodyPhoto,
  BodyPose,
  BodySeries,
  BodyShape,
  BodySnapshot,
  BodyTrend,
} from "@/api/body";

/**
 * Pure pieces of Ημερολόγιο › Σώμα (ADR-158): which fields the Μέτρηση form
 * shows, reading and checking what was typed, how values and changes read,
 * the chart paths (with a schematic line when weight shows as a trend only,
 * since no number ever reaches the client then), and choosing what to compare.
 */

/** The catalog's order (ADR-158 §2). */
export const METRICS: BodyMetric[] = [
  "weight",
  "body_fat",
  "waist",
  "hips",
  "chest",
  "arm",
  "thigh",
  "neck",
  "calf",
  "arm_left",
  "arm_right",
  "thigh_left",
  "thigh_right",
];

/** The form's fields before anything was measured (mockup «measure»). */
export const DEFAULT_FIELDS: BodyMetric[] = ["weight", "body_fat", "waist", "hips", "chest", "arm", "thigh"];

/** Weight and body fat follow `weight_display`. */
export const SENSITIVE: BodyMetric[] = ["weight", "body_fat"];

/** The poses a snapshot offers slots for. */
export const POSES: Exclude<BodyPose, "other">[] = ["front", "side", "back"];

export const TRENDS: BodyTrend[] = ["steady", "slightly_down", "down", "slightly_up", "up"];

export const RANGES = ["1m", "3m", "1y", "all"] as const;

export const isSensitive = (metric: BodyMetric) => SENSITIVE.includes(metric);

const byCatalog = (a: BodyMetric, b: BodyMetric) => METRICS.indexOf(a) - METRICS.indexOf(b);

/** Metrics a snapshot holds, shown or withheld, in catalog order. */
export function recordedMetrics(snapshot: Pick<BodySnapshot, "metrics" | "withheld_metrics">): BodyMetric[] {
  const keys = new Set<BodyMetric>([
    ...(Object.keys(snapshot.metrics ?? {}) as BodyMetric[]),
    ...(snapshot.withheld_metrics ?? []),
  ]);
  return METRICS.filter((metric) => keys.has(metric));
}

/**
 * The form's fields: the ones used last time first, then the usual ones,
 * and every other metric behind «+ Άλλη μέτρηση». Extra fields the person
 * opened stay on the form.
 */
export function formFields(
  latest: Pick<BodySnapshot, "metrics" | "withheld_metrics"> | null | undefined,
  opened: BodyMetric[] = [],
): { fields: BodyMetric[]; extras: BodyMetric[] } {
  const used = latest ? recordedMetrics(latest) : [];
  const fields: BodyMetric[] = [...used];
  for (const metric of DEFAULT_FIELDS) if (!fields.includes(metric)) fields.push(metric);
  for (const metric of [...opened].sort(byCatalog)) if (!fields.includes(metric)) fields.push(metric);
  return { fields, extras: METRICS.filter((metric) => !fields.includes(metric)) };
}

/** A typed value: `null` when empty, `NaN` when it is not a number. Takes «72,4» and «72.4». */
export function parseMetricInput(text: string): number | null {
  const trimmed = text.trim().replace(/\s+/g, "");
  if (!trimmed) return null;
  const normalized = trimmed.replace(",", ".");
  if (!/^\d+(?:\.\d+)?$/.test(normalized)) return Number.NaN;
  return Number(normalized);
}

export type MetricError = "invalid" | "range";

export type MeasureCheck = {
  ok: boolean;
  /** Nothing typed and no photo. */
  empty: boolean;
  errors: Partial<Record<BodyMetric, MetricError>>;
  metrics: Partial<Record<BodyMetric, number>>;
};

/**
 * Every field is optional; a snapshot needs at least one value or photo,
 * and each value must be a number inside the catalog's range (in the
 * person's units).
 */
export function checkMeasure(
  values: Partial<Record<BodyMetric, string>>,
  photoCount: number,
  catalog: Pick<BodyCatalogEntry, "key" | "min" | "max">[],
): MeasureCheck {
  const errors: MeasureCheck["errors"] = {};
  const metrics: MeasureCheck["metrics"] = {};
  for (const [key, text] of Object.entries(values) as [BodyMetric, string | undefined][]) {
    const value = parseMetricInput(text ?? "");
    if (value === null) continue;
    if (Number.isNaN(value)) {
      errors[key] = "invalid";
      continue;
    }
    const entry = catalog.find((item) => item.key === key);
    if (entry && (value < entry.min || value > entry.max)) {
      errors[key] = "range";
      continue;
    }
    metrics[key] = value;
  }
  const hasErrors = Object.keys(errors).length > 0;
  const empty = !hasErrors && Object.keys(metrics).length === 0 && photoCount === 0;
  return { ok: !hasErrors && !empty, empty, errors, metrics };
}

/**
 * The metrics of an edit (merged by the server): changed values, and `null`
 * for a value that was cleared. Withheld metrics are never sent back.
 */
export function metricsPatch(
  before: BodyMetrics,
  after: Partial<Record<BodyMetric, number>>,
): Partial<Record<BodyMetric, number | null>> {
  const patch: Partial<Record<BodyMetric, number | null>> = {};
  for (const metric of METRICS) {
    const old = before[metric];
    const next = after[metric];
    if (next !== undefined && next !== old) patch[metric] = next;
    else if (next === undefined && old !== undefined) patch[metric] = null;
  }
  return patch;
}

/** What the form starts with when editing: the shown values, in the locale's decimal sign. */
export function initialValues(metrics: BodyMetrics, locale: string): Partial<Record<BodyMetric, string>> {
  const values: Partial<Record<BodyMetric, string>> = {};
  for (const [key, value] of Object.entries(metrics) as [BodyMetric, number | undefined][]) {
    if (typeof value === "number") values[key] = formatNumber(value, locale);
  }
  return values;
}

export function formatNumber(value: number, locale: string, digits = 1) {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: digits, useGrouping: false }).format(value);
}

/** «72,4 kg», «22 %». */
export function formatMetric(value: number, unit: string, locale: string) {
  return `${formatNumber(value, locale)} ${unit}`;
}

/** «−0,8 kg», «+1 cm», «0 cm», with a real minus sign. */
export function formatDelta(delta: number, unit: string, locale: string) {
  const rounded = Math.round(delta * 10) / 10;
  const magnitude = formatNumber(Math.abs(rounded), locale);
  const sign = rounded > 0 ? "+" : rounded < 0 ? "−" : "";
  return `${sign}${magnitude} ${unit}`;
}

/** The unit of a metric from the catalog, with a sensible fallback. */
export function unitOf(metric: BodyMetric, catalog: Pick<BodyCatalogEntry, "key" | "unit">[], units: "metric" | "imperial") {
  const found = catalog.find((entry) => entry.key === metric)?.unit;
  if (found) return found;
  if (metric === "body_fat") return "%";
  if (metric === "weight") return units === "imperial" ? "lb" : "kg";
  return units === "imperial" ? "in" : "cm";
}

/** The change since the previous snapshot, on the first metric both show as numbers. */
export function snapshotChange(
  current: Pick<BodySnapshot, "metrics">,
  previous: Pick<BodySnapshot, "metrics"> | null | undefined,
): { metric: BodyMetric; delta: number } | null {
  if (!previous) return null;
  for (const metric of METRICS) {
    const now = current.metrics[metric];
    const before = previous.metrics[metric];
    if (typeof now === "number" && typeof before === "number") {
      return { metric, delta: Math.round((now - before) * 10) / 10 };
    }
  }
  return null;
}

/** Up to three shown values of a snapshot, for its one-line summary. */
export function summaryMetrics(snapshot: Pick<BodySnapshot, "metrics">, limit = 3): { metric: BodyMetric; value: number }[] {
  return METRICS.filter((metric) => typeof snapshot.metrics[metric] === "number")
    .slice(0, limit)
    .map((metric) => ({ metric, value: snapshot.metrics[metric] as number }));
}

/** Ready photo of a pose in a snapshot. */
export function photoOf(snapshot: Pick<BodySnapshot, "photos"> | null | undefined, pose: BodyPose): BodyPhoto | null {
  return snapshot?.photos.find((photo) => photo.pose === pose) ?? null;
}

/** Poses both snapshots have a ready photo of. */
export function sharedPoses(a: Pick<BodySnapshot, "photos"> | null | undefined, b: Pick<BodySnapshot, "photos"> | null | undefined): BodyPose[] {
  const ready = (snapshot: Pick<BodySnapshot, "photos"> | null | undefined, pose: BodyPose) =>
    Boolean(snapshot?.photos.some((photo) => photo.pose === pose && photo.status === "ready"));
  return (["front", "side", "back", "other"] as BodyPose[]).filter((pose) => ready(a, pose) && ready(b, pose));
}

/** The comparison's defaults: the first and the latest snapshot (newest-first list in). */
export function defaultComparePair(snapshots: Pick<BodySnapshot, "id" | "taken_at">[]): { from: string; to: string } | null {
  if (snapshots.length < 2) return null;
  const sorted = [...snapshots].sort((a, b) => a.taken_at.localeCompare(b.taken_at));
  return { from: sorted[0].id, to: sorted[sorted.length - 1].id };
}

/** The deltas the compare screen lists: numbers where shown, the direction word otherwise. */
export type DeltaRow = { metric: BodyMetric; kind: "number"; delta: number } | { metric: BodyMetric; kind: "trend"; direction: BodyTrend | null };

export function toDeltaRows(deltas: BodyDelta[]): DeltaRow[] {
  return deltas.map((row) =>
    typeof row.delta === "number"
      ? { metric: row.metric, kind: "number", delta: row.delta }
      : { metric: row.metric, kind: "trend", direction: row.direction ?? null },
  );
}

/** The chart paths of real values: a thin line of readings and a thick smoothed one. */
export function seriesPaths(points: BodySeries["points"], width: number, height: number, pad = 4) {
  if (points.length === 0) return { raw: "", smoothed: "" };
  const all = points.flatMap((point) => [point.value, point.smoothed]);
  const min = Math.min(...all);
  const max = Math.max(...all);
  const span = max - min || 1;
  const x = (index: number) => (points.length === 1 ? width / 2 : (index * width) / (points.length - 1));
  const y = (value: number) => height - pad - ((value - min) / span) * (height - pad * 2);
  const path = (pick: (point: BodySeries["points"][number]) => number) =>
    points.map((point, index) => `${index ? "L" : "M"}${x(index).toFixed(1)},${y(pick(point)).toFixed(1)}`).join("");
  return { raw: path((point) => point.value), smoothed: path((point) => point.smoothed) };
}

/**
 * The line for «Μόνο τάση», from the server's `shape`: the real smoothed
 * series normalized to 0..1 (no scale, no values). 1 is the top of the range.
 * Points are spaced by time; a single point draws a short flat line.
 */
export function shapePath(shape: BodyShape | null | undefined, width: number, height: number, pad = 6): string {
  if (!shape || shape.length === 0) return "";
  const times = shape.map((point) => Date.parse(point.at));
  const first = times[0];
  const span = times[times.length - 1] - first;
  const f = (value: number) => value.toFixed(1);
  const y = (value: number) => height - pad - Math.min(1, Math.max(0, value)) * (height - pad * 2);
  if (shape.length === 1) return `M0,${f(y(shape[0].y))}L${f(width)},${f(y(shape[0].y))}`;
  const x = (index: number) => (span > 0 ? ((times[index] - first) / span) * width : (index * width) / (shape.length - 1));
  return shape.map((point, index) => `${index ? "L" : "M"}${f(x(index))},${f(y(point.y))}`).join("");
}

/** The first and last shown value of a series and the change between them. */
export function seriesSummary(points: BodySeries["points"]): { latest: number; change: number | null } | null {
  if (points.length === 0) return null;
  const latest = points[points.length - 1].value;
  const change = points.length > 1 ? Math.round((latest - points[0].value) * 10) / 10 : null;
  return { latest, change };
}

/**
 * Whether to ask «Πώς θες να βλέπεις το βάρος;»: the first weight ever typed,
 * while the choice is still the default and was not answered on this device.
 */
export function shouldAskWeightDisplay(options: {
  typedWeight: boolean;
  weightDisplay: "number" | "trend" | "hidden";
  history: Pick<BodySnapshot, "metrics" | "withheld_metrics">[];
  answered: boolean;
}): boolean {
  if (!options.typedWeight || options.answered || options.weightDisplay !== "number") return false;
  return !options.history.some((snapshot) => snapshot.metrics.weight !== undefined || snapshot.withheld_metrics.includes("weight"));
}

/** A `datetime-local` value of an ISO moment in the browser's zone. */
export function toLocalInput(iso: string | Date): string {
  const date = typeof iso === "string" ? new Date(iso) : iso;
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/** The change of every metric two snapshots both show as numbers (the coach view computes its own). */
export function metricDeltas(from: Pick<BodySnapshot, "metrics">, to: Pick<BodySnapshot, "metrics">): BodyDelta[] {
  return METRICS.flatMap((metric) => {
    const a = from.metrics[metric];
    const b = to.metrics[metric];
    if (typeof a !== "number" || typeof b !== "number") return [];
    return [{ metric, delta: Math.round((b - a) * 10) / 10, direction: null }];
  });
}
