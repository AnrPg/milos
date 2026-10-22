"use client";

import { useLocale, useTranslations } from "next-intl";

import { formatLocalIsoDate, parseLocalDate } from "@/components/schedule/calendar-window";

import { weekStart } from "./WeekStrip";

/** The six weeks the month grid shows: from the Monday on or before the 1st. */
export const MONTH_GRID_DAYS = 42;

export function monthGridStart(isoDate: string) {
  const date = parseLocalDate(isoDate);
  date.setDate(1);
  return weekStart(formatLocalIsoDate(date));
}

export function shiftMonth(isoDate: string, months: number) {
  const date = parseLocalDate(isoDate);
  const day = date.getDate();
  date.setDate(1);
  date.setMonth(date.getMonth() + months);
  const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
  date.setDate(Math.min(day, lastDay));
  return formatLocalIsoDate(date);
}

function shift(isoDate: string, days: number) {
  const date = parseLocalDate(isoDate);
  date.setDate(date.getDate() + days);
  return formatLocalIsoDate(date);
}

/** A busy day shows at most this many dots, then a «+» (board 2, Q4). */
const MAX_DOTS = 3;

/** One day's matching classes, and how many of them the member booked. */
export type DayCount = { total: number; mine: number };

/**
 * The month view (plan §5a decision 7): one dot per class that matches the
 * filters, the member's own bookings green and first, at most three and a
 * «+» beyond; tapping a date opens the day view on it.
 */
export function MonthGrid({
  selectedDate,
  today: todayKey,
  counts,
  onSelect,
}: {
  selectedDate: string;
  /** ADR-179: the gym's today ("YYYY-MM-DD"); the device's when absent. */
  today?: string;
  counts: Map<string, DayCount>;
  onSelect: (isoDate: string) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const start = monthGridStart(selectedDate);
  const month = parseLocalDate(selectedDate).getMonth();
  const today = todayKey ?? formatLocalIsoDate(new Date());
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "narrow" });
  const full = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" });
  const days = Array.from({ length: MONTH_GRID_DAYS }, (_, index) => shift(start, index));

  return (
    <div role="grid" aria-label={t("monthAria")} className="flex flex-col gap-1">
      <div role="row" className="grid grid-cols-7 gap-1">
        {days.slice(0, 7).map((day) => (
          <span
            key={day}
            role="columnheader"
            className="text-center text-[11px] font-semibold"
            style={{ color: "var(--dim)" }}
          >
            {weekday.format(parseLocalDate(day))}
          </span>
        ))}
      </div>
      {Array.from({ length: MONTH_GRID_DAYS / 7 }, (_, week) => (
        <div key={week} role="row" className="grid grid-cols-7 gap-1">
          {days.slice(week * 7, week * 7 + 7).map((day) => {
            const date = parseLocalDate(day);
            const inMonth = date.getMonth() === month;
            const selected = day === selectedDate;
            const { total, mine } = counts.get(day) ?? { total: 0, mine: 0 };
            const dots = Math.min(total, MAX_DOTS);
            return (
              <button
                key={day}
                type="button"
                role="gridcell"
                aria-selected={selected}
                aria-current={day === today ? "date" : undefined}
                aria-label={`${full.format(date)}, ${t("classesOnDay", { count: total })}`}
                onClick={() => onSelect(day)}
                className="flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-sm font-bold"
                style={{
                  // Today is what is alive now: Spark, unless it is the Dojo-selected day.
                  background: selected ? "var(--primary)" : day === today ? "var(--spark)" : "transparent",
                  color: selected
                    ? "var(--primary-contrast)"
                    : day === today
                      ? "var(--spark-contrast)"
                      : inMonth
                        ? "var(--text-soft)"
                        : "var(--dim)",
                  opacity: inMonth ? 1 : 0.45,
                }}
              >
                {date.getDate()}
                <span aria-hidden="true" className="flex h-2 items-center gap-0.5">
                  {Array.from({ length: dots }, (_, index) => (
                    <span
                      key={index}
                      className="h-1 w-1 rounded-full"
                      style={{
                        background: index < mine ? "var(--success)" : selected ? "var(--bg)" : "var(--primary)",
                      }}
                    />
                  ))}
                  {total > MAX_DOTS ? <span className="text-[9px] leading-none">+</span> : null}
                </span>
              </button>
            );
          })}
        </div>
      ))}
    </div>
  );
}
