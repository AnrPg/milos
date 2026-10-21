import type { DailyStatPoint, DailyStats } from "@/api/devices";

/**
 * Πρόοδος › Ρυθμός ηρεμίας (ADR-161, board 16 Q4 A): what the card shows,
 * as plain numbers. No grades, no targets, no advice: the latest reading,
 * the period's average and the shape of the line.
 */
export type RestingHrView = {
  latest: DailyStatPoint;
  average: number;
  days: number;
  low: number;
  high: number;
  sources: string[];
  /** SVG polyline points, oldest first, or null with fewer than two days. */
  line: string | null;
};

/** One value per day: devices that sent the same day are averaged. */
export function dailyValues(points: DailyStatPoint[]): Array<{ on: string; value: number }> {
  const byDay = new Map<string, number[]>();
  for (const point of points) byDay.set(point.on, [...(byDay.get(point.on) ?? []), point.value]);
  return [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([on, values]) => ({ on, value: Math.round(values.reduce((sum, value) => sum + value, 0) / values.length) }));
}

export function sparkline(values: number[], width: number, height: number): string | null {
  if (values.length < 2) return null;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min;
  const step = width / (values.length - 1);
  return values
    .map((value, index) => {
      const x = Math.round(index * step * 10) / 10;
      const y = Math.round((span === 0 ? height / 2 : height - ((value - min) / span) * height) * 10) / 10;
      return `${x},${y}`;
    })
    .join(" ");
}

/** The card's content, or null when there is nothing to show (no card). */
export function restingHrView(stats: DailyStats | null | undefined, width = 240, height = 48): RestingHrView | null {
  if (!stats || !Array.isArray(stats.points) || stats.points.length === 0) return null;
  const days = dailyValues(stats.points);
  const values = days.map((day) => day.value);
  const latest = stats.latest ?? stats.points[stats.points.length - 1];
  const average = stats.average ?? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
  return {
    latest,
    average,
    days: days.length,
    low: Math.min(...values),
    high: Math.max(...values),
    sources: stats.sources?.length ? stats.sources : [latest.source],
    line: sparkline(values, width, height),
  };
}
