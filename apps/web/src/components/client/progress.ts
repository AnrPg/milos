import type { ProgressWeek, ScoreHistorySeries } from "@/api/content";

export type WeeklyMetric = "sessions" | "minutes";

export type WeeklyBar = {
  week_start: string;
  value: number;
  /** Bar height as a share of the tallest week, 0–100. */
  percent: number;
};

/** Oldest-first bars for the last `weeks` weeks, scaled to the busiest week. */
export function scaleWeekly(weekly: ProgressWeek[], metric: WeeklyMetric, weeks = 12): WeeklyBar[] {
  const ordered = [...weekly]
    .sort((a, b) => a.week_start.localeCompare(b.week_start))
    .slice(-weeks);
  const max = Math.max(0, ...ordered.map((week) => week[metric]));

  return ordered.map((week) => ({
    week_start: week.week_start,
    value: week[metric],
    percent: max > 0 ? Math.round((week[metric] / max) * 100) : 0,
  }));
}

/**
 * Numeric form of a score for charting: plain numbers, numeric strings and
 * clock times (`m:ss`, `h:mm:ss`, as seconds). Anything else is not charted.
 */
export function numericScore(value: number | string): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const text = value.trim();
  if (/^-?\d+(\.\d+)?$/.test(text)) return Number(text);
  if (/^\d+(:[0-5]\d){1,2}$/.test(text)) {
    return text.split(":").reduce((total, part) => total * 60 + Number(part), 0);
  }
  return null;
}

/**
 * SVG polyline points for a small score line, or null when fewer than two
 * points are numeric. The y axis is flipped so higher values sit higher.
 */
export function sparklinePoints(
  series: Pick<ScoreHistorySeries, "points">,
  width: number,
  height: number,
): string | null {
  const values = series.points
    .map((point) => numericScore(point.value))
    .filter((value): value is number => value != null);
  if (values.length < 2) return null;

  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min;
  const step = width / (values.length - 1);

  return values
    .map((value, index) => {
      const x = index * step;
      const y = span === 0 ? height / 2 : height - ((value - min) / span) * height;
      return `${round(x)},${round(y)}`;
    })
    .join(" ");
}

function round(value: number) {
  return Math.round(value * 10) / 10;
}

export type SourceShare = { source: string; count: number; percent: number };

/** Where completed sessions came from, largest first. */
export function sourceShares(sources: Record<string, number>): SourceShare[] {
  const total = Object.values(sources).reduce((sum, count) => sum + count, 0);
  return Object.entries(sources)
    .filter(([, count]) => count > 0)
    .map(([source, count]) => ({
      source,
      count,
      percent: total > 0 ? Math.round((count / total) * 100) : 0,
    }))
    .sort((a, b) => b.count - a.count || a.source.localeCompare(b.source));
}
