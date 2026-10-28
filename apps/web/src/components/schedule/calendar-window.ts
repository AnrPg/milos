import { startOfDayInZone } from "@/lib/zoned-time";

/** 1 is the day view: one day's classes, opened from a month cell. */
export type ScheduleDays = 1 | 3 | 7 | 30;

export type ScheduleWindowBounds = {
  currentMonthKey: string;
  monthLabel: string | null;
  queryEndAt: string;
  queryStartAt: string;
  visibleDates: string[];
};

const dayFormatter = new Intl.DateTimeFormat("en-US", {
  month: "long",
  year: "numeric",
});

/**
 * The days a schedule view shows and the window it asks for. ADR-179: the
 * dates are the gym's, so the query runs from the gym's midnight (`zone`;
 * the device's clock without one).
 */
export function buildScheduleWindow(startDate: string, days: ScheduleDays, zone: string | null = null): ScheduleWindowBounds {
  const anchor = parseLocalDate(startDate);

  if (days === 30) {
    return buildMonthWindow(anchor, zone);
  }

  const visibleDates = enumerateDates(anchor, days);
  const end = new Date(anchor);
  end.setDate(end.getDate() + days);

  return {
    currentMonthKey: monthKey(anchor),
    monthLabel: null,
    queryStartAt: startOfDayInZone(formatLocalIsoDate(anchor), zone).toISOString(),
    queryEndAt: startOfDayInZone(formatLocalIsoDate(end), zone).toISOString(),
    visibleDates,
  };
}

export function formatLocalIsoDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function localDateKey(date: Date) {
  return formatLocalIsoDate(date);
}

export function monthKey(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export function parseLocalDate(isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(year, month - 1, day, 0, 0, 0, 0);
}

function buildMonthWindow(anchor: Date, zone: string | null): ScheduleWindowBounds {
  const monthStart = new Date(anchor.getFullYear(), anchor.getMonth(), 1, 0, 0, 0, 0);
  const nextMonthStart = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 1, 0, 0, 0, 0);
  const monthEnd = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0, 0, 0, 0, 0);
  const gridStart = new Date(monthStart);
  const gridEnd = new Date(monthEnd);

  gridStart.setDate(gridStart.getDate() - gridStart.getDay());
  gridEnd.setDate(gridEnd.getDate() + (6 - gridEnd.getDay()) + 1);

  return {
    currentMonthKey: monthKey(anchor),
    monthLabel: dayFormatter.format(monthStart),
    queryStartAt: startOfDayInZone(formatLocalIsoDate(monthStart), zone).toISOString(),
    queryEndAt: startOfDayInZone(formatLocalIsoDate(nextMonthStart), zone).toISOString(),
    visibleDates: enumerateDates(gridStart, differenceInDays(gridStart, gridEnd)),
  };
}

function differenceInDays(start: Date, end: Date) {
  return Math.round((end.getTime() - start.getTime()) / 86_400_000);
}

function enumerateDates(start: Date, days: number) {
  return Array.from({ length: days }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return formatLocalIsoDate(date);
  });
}
