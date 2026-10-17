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

/** A busy day shows at most this many dots. */
const MAX_DOTS = 4;

/**
 * The month view (plan §5a decision 7): one dot per class that matches the
 * filters; tapping a date opens the day view on it.
 */
export function MonthGrid({
  selectedDate,
  counts,
  onSelect,
}: {
  selectedDate: string;
  counts: Map<string, number>;
  onSelect: (isoDate: string) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const start = monthGridStart(selectedDate);
  const month = parseLocalDate(selectedDate).getMonth();
  const today = formatLocalIsoDate(new Date());
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
            const count = counts.get(day) ?? 0;
            return (
              <button
                key={day}
                type="button"
                role="gridcell"
                aria-selected={selected}
                aria-current={day === today ? "date" : undefined}
                aria-label={`${full.format(date)}, ${t("classesOnDay", { count })}`}
                onClick={() => onSelect(day)}
                className="flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl text-sm font-bold"
                style={{
                  background: selected ? "var(--primary)" : "transparent",
                  color: selected ? "var(--bg)" : inMonth ? "var(--text-soft)" : "var(--dim)",
                  opacity: inMonth ? 1 : 0.45,
                  boxShadow: !selected && day === today ? "inset 0 0 0 1px var(--border)" : undefined,
                }}
              >
                {date.getDate()}
                <span aria-hidden="true" className="flex h-1.5 items-center gap-0.5">
                  {Array.from({ length: Math.min(count, MAX_DOTS) }, (_, index) => (
                    <span
                      key={index}
                      className="h-1 w-1 rounded-full"
                      style={{ background: selected ? "var(--bg)" : "var(--primary)" }}
                    />
                  ))}
                </span>
              </button>
            );
          })}
        </div>
      ))}
    </div>
  );
}
