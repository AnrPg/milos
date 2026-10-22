"use client";

import { useLocale, useTranslations } from "next-intl";

import { formatLocalIsoDate, parseLocalDate } from "@/components/schedule/calendar-window";

/** Monday of the week holding `isoDate`. */
export function weekStart(isoDate: string) {
  const date = parseLocalDate(isoDate);
  date.setDate(date.getDate() - ((date.getDay() + 6) % 7));
  return formatLocalIsoDate(date);
}

function shift(isoDate: string, days: number) {
  const date = parseLocalDate(isoDate);
  date.setDate(date.getDate() + days);
  return formatLocalIsoDate(date);
}

/** The day view's week strip (plan §5a decision 7). */
export function WeekStrip({
  selectedDate,
  onSelect,
}: {
  selectedDate: string;
  onSelect: (isoDate: string) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const start = weekStart(selectedDate);
  const today = formatLocalIsoDate(new Date());
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short" });
  const full = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" });
  const days = Array.from({ length: 7 }, (_, index) => shift(start, index));
  const arrow = "grid h-11 w-7 shrink-0 place-items-center rounded-xl text-lg";

  return (
    <nav aria-label={t("weekAria")} className="flex items-center gap-1">
      <button
        type="button"
        onClick={() => onSelect(shift(selectedDate, -7))}
        aria-label={t("previousWeek")}
        className={arrow}
        style={{ color: "var(--dim)" }}
      >
        <span aria-hidden="true">‹</span>
      </button>
      <ol className="grid flex-1 grid-cols-7 gap-1">
        {days.map((day) => {
          const date = parseLocalDate(day);
          const selected = day === selectedDate;
          return (
            <li key={day}>
              <button
                type="button"
                onClick={() => onSelect(day)}
                aria-pressed={selected}
                aria-label={full.format(date)}
                aria-current={day === today ? "date" : undefined}
                className="flex min-h-12 w-full flex-col items-center justify-center rounded-xl text-[11px] font-semibold"
                style={{
                  // Today is what is alive now: Spark, unless it is the Dojo-selected day.
                  background: selected ? "var(--primary)" : day === today ? "var(--spark)" : "transparent",
                  color: selected ? "var(--primary-contrast)" : day === today ? "var(--spark-contrast)" : "var(--dim)",
                }}
              >
                {weekday.format(date)}
                <span className="text-base font-bold" style={{ color: selected ? "var(--primary-contrast)" : day === today ? "var(--spark-contrast)" : "var(--text-soft)" }}>
                  {date.getDate()}
                </span>
              </button>
            </li>
          );
        })}
      </ol>
      <button
        type="button"
        onClick={() => onSelect(shift(selectedDate, 7))}
        aria-label={t("nextWeek")}
        className={arrow}
        style={{ color: "var(--dim)" }}
      >
        <span aria-hidden="true">›</span>
      </button>
    </nav>
  );
}
