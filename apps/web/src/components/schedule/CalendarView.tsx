"use client";

import type { ScheduleSlot } from "@/api/schedule";
import { buildScheduleWindow, localDateKey, monthKey, parseLocalDate, trainingTypeLabel, type ScheduleDays } from "@/components/schedule/calendar-window";
import { WORKOUT_TYPE_COLORS } from "@/lib/workout-colors";

type CalendarViewProps = {
  days: ScheduleDays;
  startDate: string;
  slots: ScheduleSlot[];
  isAdmin: boolean;
  onSelectSlot: (slot: ScheduleSlot) => void;
  onCreateSlot: (isoDate: string) => void;
};

function formatDayLabel(isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12, 0, 0);
  return new Intl.DateTimeFormat("en-US", { weekday: "long", month: "short", day: "numeric" }).format(date);
}

function formatDayLabelCompact(isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12, 0, 0);
  const weekday = new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(date);
  return { weekday, day };
}

function formatTime(isoString: string) {
  return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date(isoString));
}

const todayKey = localDateKey(new Date());

export function CalendarView({ days, startDate, slots, isAdmin, onSelectSlot, onCreateSlot }: CalendarViewProps) {
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
          <h2 className="text-lg font-bold" style={{ color: "#F0EDF8" }}>{monthLabel}</h2>
        </div>
        {/* Day-of-week header */}
        <div className="mb-1 grid grid-cols-7 gap-1">
          {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label) => (
            <div key={label} className="py-1 text-center text-[10px] font-semibold uppercase tracking-[0.16em]" style={{ color: "#55556a" }}>
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
                  background: outsideMonth ? "transparent" : "#111118",
                  border: `1px solid ${isToday ? "#d95d39" : outsideMonth ? "transparent" : "#1a1a28"}`,
                }}
              >
                <div className="flex items-center justify-between">
                  <span
                    className="flex h-5 w-5 items-center justify-center rounded-full text-xs font-bold"
                    style={{
                      background: isToday ? "#d95d39" : "transparent",
                      color: isToday ? "#fff" : outsideMonth ? "#2a2a3a" : "#F0EDF8",
                    }}
                  >
                    {dayNum}
                  </span>
                  {isAdmin && !outsideMonth ? (
                    <button
                      className="text-[11px] font-bold leading-none text-[#d95d39] hover:opacity-70"
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      +
                    </button>
                  ) : null}
                </div>
                {daySlots.slice(0, 3).map((slot) => {
                  const slotColor = WORKOUT_TYPE_COLORS[slot.training_type] ?? "#d95d39";
                  return (
                    <button
                      key={slot.id}
                      className="mt-0.5 w-full truncate rounded px-1 py-0.5 text-left text-[9px] font-semibold transition-opacity hover:opacity-80"
                      style={{ background: `${slotColor}26`, color: slotColor }}
                      onClick={() => onSelectSlot(slot)}
                      type="button"
                    >
                      {formatTime(slot.scheduled_at)} {trainingTypeLabel(slot.training_type)}
                    </button>
                  );
                })}
                {daySlots.length > 3 ? (
                  <p className="mt-0.5 text-[9px]" style={{ color: "#55556a" }}>+{daySlots.length - 3} more</p>
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
        className={`grid min-w-full gap-4 ${days === 3 ? "md:grid-cols-3" : "md:grid-cols-7"}`}
      >
        {visibleDates.map((date) => {
          const daySlots = slotMap[date] ?? [];
          const { weekday, day } = formatDayLabelCompact(date);
          const isToday = date === todayKey;

          return (
            <section
              className="rounded-[1.8rem] p-4"
              style={{
                background: "#111118",
                border: `1px solid ${isToday ? "#d95d39" : "#1a1a28"}`,
                minHeight: days === 3 ? "16rem" : "10rem",
              }}
              key={date}
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  {days === 3 ? (
                    <>
                      <p className="text-base font-bold" style={{ color: "#F0EDF8" }}>{weekday}</p>
                      <p className="mt-0.5 text-xs">
                        <span style={{ color: "#55556a" }}>{formatDayLabel(date).split(", ").slice(1, 2).join("").split(" ")[0]} </span>
                        <span style={{ color: isToday ? "#d95d39" : "#8888aa" }}>{day}</span>
                      </p>
                    </>
                  ) : (
                    <>
                      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>{weekday}</p>
                      <p className="mt-0.5 text-lg font-bold" style={{ color: isToday ? "#d95d39" : "#F0EDF8" }}>{day}</p>
                    </>
                  )}
                </div>

                {isAdmin ? (
                  <button
                    className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                    style={{ background: "rgba(217,93,57,0.12)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                    onClick={() => onCreateSlot(date)}
                    type="button"
                  >
                    + Slot
                  </button>
                ) : null}
              </div>

              <div className="mt-4 space-y-3">
                {daySlots.length === 0 ? (
                  isAdmin ? (
                    <button
                      className="w-full rounded-[1.2rem] px-4 py-6 text-left text-sm transition-colors"
                      style={{ border: "1px dashed #1a1a28", color: "#2a2a3a" }}
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      Add the first class slot for this day.
                    </button>
                  ) : (
                    <p className="rounded-[1.2rem] px-4 py-6 text-sm" style={{ border: "1px dashed #1a1a28", color: "#2a2a3a" }}>
                      No classes scheduled for this day.
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
  const isPast = new Date(slot.scheduled_at) <= new Date();
  const isUnavailable = !slot.current_user_booking && (slot.spots_remaining === 0 || isPast);
  const typeColor = WORKOUT_TYPE_COLORS[slot.training_type] ?? "#d95d39";

  if (compact) {
    return (
      <button
        className="w-full truncate rounded-[0.9rem] p-2.5 text-left transition-all"
        style={{
          background: isUnavailable ? "#0d0d18" : "#151520",
          border: `1px solid ${isUnavailable ? "#111118" : "#1e1e2e"}`,
        }}
        onClick={() => onSelectSlot(slot)}
        type="button"
      >
        <p className="text-xs font-semibold" style={{ color: isUnavailable ? "#3a3a55" : "#F0EDF8" }}>
          {new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date(slot.scheduled_at))}
        </p>
        <p className="truncate text-[10px] uppercase tracking-[0.14em]" style={{ color: isUnavailable ? "#3a3a55" : typeColor }}>
          {trainingTypeLabel(slot.training_type)}
        </p>
      </button>
    );
  }

  return (
    <button
      className="w-full rounded-[1.3rem] p-4 text-left transition-all"
      style={{
        background: isUnavailable ? "#0d0d18" : "#151520",
        border: `1px solid ${isUnavailable ? "#111118" : "#1e1e2e"}`,
      }}
      onClick={() => onSelectSlot(slot)}
      type="button"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: isUnavailable ? "#3a3a55" : "#F0EDF8" }}>
            {new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date(slot.scheduled_at))}
          </p>
          <p className="mt-1 text-sm" style={{ color: isUnavailable ? "#2a2a3a" : "#8888aa" }}>
            {slot.workout?.title ?? "Workout preview unavailable"}
          </p>
        </div>
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
          style={{
            background: isUnavailable ? "#1a1a28" : `${typeColor}26`,
            color: isUnavailable ? "#3a3a55" : typeColor,
          }}
        >
          {trainingTypeLabel(slot.training_type)}
        </span>
      </div>

      <div className="mt-3 flex items-center justify-between text-xs" style={{ color: "#3a3a55" }}>
        <span>{slot.approved_booking_count}/{slot.capacity} booked</span>
        <span style={{ color: slot.current_user_booking ? "#9c799c" : isUnavailable ? "#2a2a3a" : "#55556a" }}>
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
