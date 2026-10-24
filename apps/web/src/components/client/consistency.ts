/**
 * Πρόοδος › Συνέπεια (ADR-194, mockup `heatGrid`): the calendar heatmap of
 * the range, a column per week (Monday first) and a cell per day, and the
 * weeks that reached the weekly target. Pure, so the grid is tested without
 * a browser; dates are ISO days handled in UTC so no zone shifts them.
 */

export type HeatLevel = 0 | 1 | 2 | 3;

export type HeatDay = {
  date: string;
  sessions: number;
  level: HeatLevel;
  /** After today: drawn as an empty slot, not as a day without training. */
  future: boolean;
};

export type HeatWeek = {
  week_start: string;
  sessions: number;
  onTarget: boolean;
  days: HeatDay[];
};

/** Most week columns in one strip; longer ranges wrap so 360px never scrolls sideways. */
export const MAX_STRIP_WEEKS = 26;

const DAY_MS = 86_400_000;

function addDays(iso: string, days: number): string {
  return new Date(Date.parse(`${iso}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** The member's own calendar day (YYYY-MM-DD). */
export function localToday(now = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** 0 none, 1 one session, 2 two, 3 three or more. */
export function heatLevel(sessions: number): HeatLevel {
  if (sessions <= 0) return 0;
  return sessions >= 3 ? 3 : (sessions as 1 | 2);
}

/**
 * Weeks oldest first as the API lists them, each with its seven days.
 * `target` is the weekly workout target; without one a week counts when it
 * has any session.
 */
export function consistencyGrid(
  weekly: { week_start: string; sessions: number }[],
  days: { date: string; sessions: number }[],
  today: string,
  target: number | null,
): HeatWeek[] {
  const byDay = new Map(days.map((day) => [day.date, day.sessions]));
  const goal = Math.max(1, target ?? 1);
  return [...weekly]
    .sort((left, right) => left.week_start.localeCompare(right.week_start))
    .map((week) => ({
      week_start: week.week_start,
      sessions: week.sessions,
      onTarget: week.sessions >= goal,
      days: Array.from({ length: 7 }, (_, index) => {
        const date = addDays(week.week_start, index);
        const sessions = byDay.get(date) ?? 0;
        return { date, sessions, level: heatLevel(sessions), future: date > today };
      }),
    }));
}

export function weeksOnTarget(weeks: HeatWeek[]): number {
  return weeks.filter((week) => week.onTarget).length;
}

/** Splits the weeks into strips of equal-ish width, at most `max` weeks each. */
export function heatStrips(weeks: HeatWeek[], max = MAX_STRIP_WEEKS): HeatWeek[][] {
  if (weeks.length === 0) return [];
  const count = Math.ceil(weeks.length / max);
  const size = Math.ceil(weeks.length / count);
  return Array.from({ length: count }, (_, index) => weeks.slice(index * size, (index + 1) * size)).filter(
    (strip) => strip.length > 0,
  );
}
