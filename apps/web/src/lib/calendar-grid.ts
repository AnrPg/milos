// Plain calendar maths for the date picker (ADR-182). Dates are ISO day
// strings ("2026-10-22"), never Date objects, so a picked day can't shift
// with the viewer's time zone.

export type Ymd = { year: number; month: number; day: number };

const ISO_DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

export function parseIsoDay(value: string | null | undefined): Ymd | null {
  const match = value ? ISO_DAY.exec(value) : null;
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return { year, month, day };
}

export function isoDay({ year, month, day }: Ymd) {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function daysInMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** 0 = Sunday … 6 = Saturday. */
export function weekday({ year, month, day }: Ymd) {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

export function addDays(date: Ymd, days: number): Ymd {
  const moved = new Date(Date.UTC(date.year, date.month - 1, date.day + days));
  return { year: moved.getUTCFullYear(), month: moved.getUTCMonth() + 1, day: moved.getUTCDate() };
}

/** Same day in another month, clamped to that month's length (31 Jan + 1 month = 28/29 Feb). */
export function addMonths(date: Ymd, months: number): Ymd {
  const index = date.year * 12 + (date.month - 1) + months;
  const year = Math.floor(index / 12);
  const month = (index % 12) + 1;
  return { year, month, day: Math.min(date.day, daysInMonth(year, month)) };
}

export function compareDays(a: Ymd, b: Ymd) {
  return isoDay(a) < isoDay(b) ? -1 : isoDay(a) > isoDay(b) ? 1 : 0;
}

export function todayYmd(now = new Date()): Ymd {
  return { year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() };
}

/** The locale's first day of the week (0 = Sunday, 1 = Monday), Monday when the browser can't say. */
export function firstDayOfWeek(locale: string) {
  try {
    const info = new Intl.Locale(locale) as Intl.Locale & {
      getWeekInfo?: () => { firstDay: number };
      weekInfo?: { firstDay: number };
    };
    const firstDay = info.getWeekInfo?.().firstDay ?? info.weekInfo?.firstDay;
    if (firstDay) return firstDay % 7;
  } catch {
    // Fall through to Monday.
  }
  return 1;
}

/**
 * The 6×7 grid shown for a month: whole weeks starting on `weekStart`, with
 * the trailing days of the month before and the leading days of the next.
 */
export function monthGrid(year: number, month: number, weekStart: number): Ymd[] {
  const first = { year, month, day: 1 };
  const lead = (weekday(first) - weekStart + 7) % 7;
  const start = addDays(first, -lead);
  return Array.from({ length: 42 }, (_, index) => addDays(start, index));
}

export function withinRange(date: Ymd, min: Ymd | null, max: Ymd | null) {
  return (!min || compareDays(date, min) >= 0) && (!max || compareDays(date, max) <= 0);
}

const TIME = /^(\d{1,2}):(\d{2})/;

export function parseTime(value: string | null | undefined): { hour: number; minute: number } | null {
  const match = value ? TIME.exec(value) : null;
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour < 24 && minute < 60 ? { hour, minute } : null;
}

export function formatTime(hour: number, minute: number) {
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}
