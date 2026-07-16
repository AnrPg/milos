"use client";





import {useUiTranslations} from "@/i18n/ui";
import type { ScheduleSlot } from "@/api/schedule";
import { useLocale } from "next-intl";
import { buildScheduleWindow, localDateKey, monthKey, parseLocalDate, type ScheduleDays } from "@/components/schedule/calendar-window";
import { WORKOUT_TYPE_COLORS } from "@/lib/workout-colors";

type CalendarViewProps = {
  days: ScheduleDays;
  startDate: string;
  slots: ScheduleSlot[];
  isAdmin: boolean;
  onSelectSlot: (slot: ScheduleSlot) => void;
  onCreateSlot: (isoDate: string) => void;
};

function formatDayLabel(locale: string, isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12, 0, 0);
  return new Intl.DateTimeFormat(locale, { weekday: "long", month: "short", day: "numeric" }).format(date);
}

function formatDayLabelCompact(locale: string, isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12, 0, 0);
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short" }).format(date);
  return { weekday, day };
}

function formatTime(locale: string, isoString: string) {
  return new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" }).format(new Date(isoString));
}

const todayKey = localDateKey(new Date());

export function CalendarView({ days, startDate, slots, isAdmin, onSelectSlot, onCreateSlot }: CalendarViewProps) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const { currentMonthKey, visibleDates, monthLabel } = buildScheduleWindow(startDate, days);
  const slotMap = visibleDates.reduce<Record<string, ScheduleSlot[]>>((acc, date) => {
    acc[date] = [];
    return acc;
  }, {});

  slots.forEach((slot) => {
    const dateKey = localDateKey(new Date(slot.scheduled_at));
    slotMap[dateKey] = [...(slotMap[dateKey] ?? []), slot].sort((a, b) =>
      a.scheduled_at.localeCompare(b.scheduled_at),
    );
  });

  // Month view: compact Google-Calendar-style grid
  if (days === 30) {
    return (
      <div>
        <div className="mb-3 flex items-center">
          <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{monthLabel}</h2>
        </div>
        {/* Day-of-week header */}
        <div className="mb-1 grid grid-cols-7 gap-1">
          {Array.from({ length: 7 }, (_, index) => {
            const date = new Date(2026, 5, 1 + index, 12, 0, 0);
            return new Intl.DateTimeFormat(locale, { weekday: "short" }).format(date);
          }).map((label) => (
            <div key={label} className="py-1 text-center text-[10px] font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
              {label}
            </div>
          ))}
        </div>
        {/* Date cells */}
        <div className="grid grid-cols-7 gap-1">
          {visibleDates.map((date) => {
            const daySlots = slotMap[date] ?? [];
            const outsideMonth = monthKey(parseLocalDate(date)) !== currentMonthKey;
            const isToday = date === todayKey;
            const dayNum = parseInt(date.split("-")[2], 10);

            return (
              <section
                key={date}
                className="min-h-[5.5rem] rounded-xl p-1.5"
                style={{
                  background: outsideMonth ? "transparent" : "var(--panel)",
                  border: `1px solid ${isToday ? "var(--primary)" : outsideMonth ? "transparent" : "var(--border)"}`,
                }}
              >
                <div className="flex items-center justify-between">
                  <span
                    className="flex h-5 w-5 items-center justify-center rounded-full text-xs font-bold"
                    style={{
                      background: isToday ? "var(--primary)" : "transparent",
                      color: isToday ? "var(--primary-contrast)" : outsideMonth ? "var(--border-strong)" : "var(--text)",
                    }}
                  >
                    {dayNum}
                  </span>
                  {isAdmin && !outsideMonth ? (
                    <button
                      className="text-[11px] font-bold leading-none text-[var(--primary)] hover:opacity-70"
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      +
                    </button>
                  ) : null}
                </div>
                {daySlots.slice(0, 3).map((slot) => {
                  const slotColor = WORKOUT_TYPE_COLORS[slot.class_type.slug] ?? "var(--primary)";
                  return (
                    <button
                      key={slot.id}
                      className="mt-0.5 w-full truncate rounded px-1 py-0.5 text-start text-[9px] font-semibold transition-opacity hover:opacity-80"
                      style={{ background: `color-mix(in srgb, ${slotColor} 15%, transparent)`, color: slotColor }}
                      onClick={() => onSelectSlot(slot)}
                      type="button"
                    >
                      {formatTime(locale, slot.scheduled_at)} {slot.class_type.name}
                    </button>
                  );
                })}
                {daySlots.length > 3 ? (
                  <p className="mt-0.5 text-[9px]" style={{ color: "var(--dim)" }}>+{daySlots.length - 3} {i18n("moree7c95b4")}</p>
                ) : null}
              </section>
            );
          })}
        </div>
      </div>
    );
  }

  // 3-day or week view: column grid
  return (
    <div className="overflow-x-auto pb-2">
      <div
        className={"grid min-w-full gap-4 " + (days === 3 ? "md:grid-cols-3" : "md:grid-cols-7")}
      >
        {visibleDates.map((date) => {
          const daySlots = slotMap[date] ?? [];
          const { weekday, day } = formatDayLabelCompact(locale, date);
          const isToday = date === todayKey;

          return (
            <section
              className="rounded-[1.8rem] p-4"
              style={{
                background: "var(--panel)",
                border: `1px solid ${isToday ? "var(--primary)" : "var(--border)"}`,
                minHeight: days === 3 ? "16rem" : "10rem",
              }}
              key={date}
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  {days === 3 ? (
                    <>
                      <p className="text-base font-bold" style={{ color: "var(--text)" }}>{weekday}</p>
                      <p className="mt-0.5 text-xs">
                        <span style={{ color: "var(--dim)" }}>{formatDayLabel(locale, date).split(", ").slice(1, 2).join("").split(" ")[0]} </span>
                        <span style={{ color: isToday ? "var(--primary)" : "var(--muted)" }}>{day}</span>
                      </p>
                    </>
                  ) : (
                    <>
                      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{weekday}</p>
                      <p className="mt-0.5 text-lg font-bold" style={{ color: isToday ? "var(--primary)" : "var(--text)" }}>{day}</p>
                    </>
                  )}
                </div>

                {isAdmin ? (
                    <button
                      className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                      style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      {i18n("slotd16d457")}
                    </button>
                  ) : null}
              </div>

              <div className="mt-4 space-y-3">
                {daySlots.length === 0 ? (
                  isAdmin ? (
                    <button
                      className="w-full rounded-[1.2rem] px-4 py-6 text-start text-sm transition-colors"
                      style={{ border: "1px dashed var(--border)", color: "var(--border-strong)" }}
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      {i18n("addTheFirstClassSlotForThisDaydf937ac")}
                    </button>
                  ) : (
                    <p className="rounded-[1.2rem] px-4 py-6 text-sm" style={{ border: "1px dashed var(--border)", color: "var(--border-strong)" }}>
                      {i18n("noClassesScheduledForThisDay28542bf")}
                    </p>
                  )
                ) : null}
                {daySlots.map((slot) => (
                  <SlotCard key={slot.id} slot={slot} compact={days === 7} onSelectSlot={onSelectSlot} />
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}

function SlotCard({ slot, compact, onSelectSlot }: { slot: ScheduleSlot; compact: boolean; onSelectSlot: (slot: ScheduleSlot) => void }) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const isPast = new Date(slot.scheduled_at) <= new Date();
  const isUnavailable = !slot.current_user_booking && (slot.spots_remaining === 0 || isPast);
  const typeColor = WORKOUT_TYPE_COLORS[slot.class_type.slug] ?? "var(--primary)";

  if (compact) {
    return (
      <button
        className="w-full truncate rounded-[0.9rem] p-2.5 text-start transition-all"
        style={{
          background: isUnavailable ? "var(--panel-muted)" : "var(--panel-muted)",
          border: `1px solid ${isUnavailable ? "var(--panel)" : "var(--border)"}`,
        }}
        onClick={() => onSelectSlot(slot)}
        type="button"
      >
        <p className="text-xs font-semibold" style={{ color: isUnavailable ? "var(--dim)" : "var(--text)" }}>
          {new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" }).format(new Date(slot.scheduled_at))}
        </p>
        <p className="truncate text-[10px] uppercase tracking-[0.14em]" style={{ color: isUnavailable ? "var(--dim)" : typeColor }}>
          {slot.class_type.name}
        </p>
      </button>
    );
  }

  return (
    <button
      className="w-full rounded-[1.3rem] p-4 text-start transition-all"
      style={{
        background: isUnavailable ? "var(--panel-muted)" : "var(--panel-muted)",
        border: `1px solid ${isUnavailable ? "var(--panel)" : "var(--border)"}`,
      }}
      onClick={() => onSelectSlot(slot)}
      type="button"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: isUnavailable ? "var(--dim)" : "var(--text)" }}>
            {new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" }).format(new Date(slot.scheduled_at))}
          </p>
          <p className="mt-1 text-sm" style={{ color: isUnavailable ? "var(--border-strong)" : "var(--muted)" }}>
          {slot.workout?.title ?? i18n("workoutPreviewUnavailable473ec36")}
          </p>
        </div>
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
          style={{
            background: isUnavailable ? "var(--border)" : `color-mix(in srgb, ${typeColor} 15%, transparent)`,
            color: isUnavailable ? "var(--dim)" : typeColor,
          }}
        >
          {slot.class_type.name}
        </span>
      </div>

      <div className="mt-3 flex items-center justify-between text-xs" style={{ color: "var(--dim)" }}>
        <span>{slot.approved_booking_count}/{slot.capacity} {i18n("booked67fbe17")}</span>
        <span style={{ color: slot.current_user_booking ? "var(--primary)" : isUnavailable ? "var(--border-strong)" : "var(--dim)" }}>
          {slotStatusLabel(slot, isPast)}
        </span>
      </div>
    </button>
  );
}

function slotStatusLabel(slot: ScheduleSlot, isPast: boolean) {
  if (slot.current_user_booking) return slot.current_user_booking.status;
  if (isPast) return "Ended";
  if (slot.spots_remaining === 0) return "Full";
  return `${slot.spots_remaining} spots left`;
}
