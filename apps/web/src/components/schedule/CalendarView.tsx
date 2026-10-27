"use client";






import {useUiTranslations} from "@/i18n/ui";
import type { ScheduleLocation, ScheduleSlot } from "@/api/schedule";
import { useLocale } from "next-intl";
import { buildScheduleWindow, monthKey, parseLocalDate, type ScheduleDays } from "@/components/schedule/calendar-window";
import { dateKeyInZone, formatInZone } from "@/lib/zoned-time";
import { WORKOUT_TYPE_COLORS } from "@/lib/workout-colors";
import { semanticLabel } from "@/i18n/presentation";
import { classStateBadge, isEventSlot, memberSlotState, slotLocationName, waitlistPositionLabel } from "@/components/schedule/member-booking";
import { ClassStateBadge } from "@/components/schedule/ClassState";
import { SPARK_CREATE_STYLE } from "@/lib/spark";
import { classWorkoutNoticeKind } from "@/components/schedule/ClassWorkoutNotice";

type CalendarViewProps = {
  days: ScheduleDays;
  startDate: string;
  slots: ScheduleSlot[];
  isAdmin: boolean;
  locations?: ScheduleLocation[];
  onSelectSlot: (slot: ScheduleSlot) => void;
  onCreateSlot: (isoDate: string) => void;
  /** ADR-179: the gym's zone; days and times are on its clock. */
  timeZone?: string | null;
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

function formatTime(locale: string, isoString: string, zone: string | null = null) {
  return formatInZone(isoString, zone, locale, { hour: "numeric", minute: "2-digit" });
}

function slotClassType(slot: ScheduleSlot) {
  return {
    name: slot.class_type?.name ?? slot.class_type_id ?? "—",
    slug: slot.class_type?.slug ?? slot.class_type_id ?? "class",
  };
}

export function CalendarView({ days, startDate, slots, isAdmin, locations, onSelectSlot, onCreateSlot, timeZone = null }: CalendarViewProps) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const todayKey = dateKeyInZone(new Date(), timeZone);
  // ADR-205: a class cannot start in the past, so past days offer no "+ Slot".
  const canAddOn = (date: string) => isAdmin && date >= todayKey;
  const { currentMonthKey, visibleDates, monthLabel } = buildScheduleWindow(startDate, days, timeZone);
  const slotMap = visibleDates.reduce<Record<string, ScheduleSlot[]>>((acc, date) => {
    acc[date] = [];
    return acc;
  }, {});

  slots.forEach((slot) => {
    const dateKey = dateKeyInZone(slot.scheduled_at, timeZone);
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
            const date = parseLocalDate(visibleDates[index] ?? visibleDates[0]);
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
                  {canAddOn(date) && !outsideMonth ? (
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
                  const classType = slotClassType(slot);
                  const slotColor = WORKOUT_TYPE_COLORS[classType.slug] ?? "var(--primary)";
                  return (
                    <button
                      key={slot.id}
                      className="mt-0.5 w-full truncate rounded px-1 py-0.5 text-start text-[9px] font-semibold transition-opacity hover:opacity-80"
                      style={{ background: `color-mix(in srgb, ${slotColor} 15%, transparent)`, color: slotColor }}
                      onClick={() => onSelectSlot(slot)}
                      type="button"
                    >
                      {formatTime(locale, slot.scheduled_at, timeZone)} {classType.name}
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

                {canAddOn(date) ? (
                    <button
                      className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                      style={SPARK_CREATE_STYLE}
                      onClick={() => onCreateSlot(date)}
                      type="button"
                    >
                      {i18n("slotd16d457")}
                    </button>
                  ) : null}
              </div>

              <div className="mt-4 space-y-3">
                {daySlots.length === 0 ? (
                  canAddOn(date) ? (
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
                  <SlotCard
                    key={slot.id}
                    slot={slot}
                    compact={days === 7}
                    isAdmin={isAdmin}
                    locationName={slotLocationName(slot, locations)}
                    onSelectSlot={onSelectSlot}
                    timeZone={timeZone}
                  />
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}

function SlotCard({
  slot,
  compact,
  isAdmin,
  locationName,
  onSelectSlot,
  timeZone,
}: {
  slot: ScheduleSlot;
  timeZone: string | null;
  compact: boolean;
  isAdmin: boolean;
  locationName: string | null;
  onSelectSlot: (slot: ScheduleSlot) => void;
}) {
  const i18n = useUiTranslations();
  const memberState = memberSlotState(slot);

  function slotStatusLabel(slot: ScheduleSlot, isPast: boolean) {
    if (memberState.kind === "waitlisted") return waitlistPositionLabel(memberState.position, i18n);
    if (slot.current_user_booking) return semanticLabel(slot.current_user_booking.status, i18n);
    if (isPast) return i18n("ended90303d8");
    if (slot.spots_remaining === 0) return isAdmin ? i18n("full10b28a8") : i18n("mbFullWaitlistOpen");
    return i18n("value0SpotsLeft3ff0ef6", {value0: slot.spots_remaining});
  }

  const locale = useLocale();
  const isPast = new Date(slot.scheduled_at) <= new Date();
  // A full class stays inviting for members because they can join the waitlist.
  // ADR-200: a cancelled class stays listed, struck through.
  const cancelled = classStateBadge(slot) === "cancelled";
  const isUnavailable =
    cancelled || (!slot.current_user_booking && (isPast || (slot.spots_remaining === 0 && isAdmin)));
  const strike = cancelled ? "line-through" : undefined;
  const details = [isEventSlot(slot) ? i18n("mbEventMarker") : null, locationName].filter(Boolean).join(" · ");
  const classType = slotClassType(slot);
  const typeColor = WORKOUT_TYPE_COLORS[classType.slug] ?? "var(--primary)";
  // ADR-176: staff see a class without its WOD as incomplete (a draft, or a
  // series class from 00:00 on its day).
  const workoutNotice = isAdmin && !isPast ? classWorkoutNoticeKind(slot) : null;
  const incompleteBadge =
    workoutNotice === "draft" || workoutNotice === "missing" ? (
      <span
        className="inline-block rounded-full px-2 py-0.5 text-[10px] font-bold"
        style={{ background: "color-mix(in srgb, var(--danger) 14%, transparent)", color: "var(--danger)" }}
      >
        {workoutNotice === "draft" ? i18n("classDraftBadge") : i18n("classWodMissingBadge")}
      </span>
    ) : null;

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
        <p className="text-xs font-semibold" style={{ color: isUnavailable ? "var(--dim)" : "var(--text)", textDecoration: strike }}>
          {formatTime(locale, slot.scheduled_at, timeZone)}
        </p>
        <p className="truncate text-[10px] uppercase tracking-[0.14em]" style={{ color: isUnavailable ? "var(--dim)" : typeColor }}>
          {classType.name}
        </p>
        {slot.my_version ? (
          <p className="truncate text-[9px] font-bold" style={{ color: "var(--primary)" }}>
            {i18n("memberProgrammingYourVersion")}
          </p>
        ) : null}
        {incompleteBadge ? <div className="mt-1 truncate">{incompleteBadge}</div> : null}
        {classStateBadge(slot) ? <div className="mt-1 truncate"><ClassStateBadge slot={slot} /></div> : null}
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
          <p className="text-sm font-semibold" style={{ color: isUnavailable ? "var(--dim)" : "var(--text)", textDecoration: strike }}>
            {formatTime(locale, slot.scheduled_at, timeZone)}
          </p>
          <p className="mt-1 text-sm" style={{ color: isUnavailable ? "var(--border-strong)" : "var(--muted)" }}>
          {slot.workout?.title ?? i18n("workoutPreviewUnavailable473ec36")}
          </p>
          {incompleteBadge ? <div className="mt-2">{incompleteBadge}</div> : null}
          {classStateBadge(slot) ? <div className="mt-2"><ClassStateBadge slot={slot} /></div> : null}
          {slot.my_version ? (
            <span
              className="mt-2 inline-block rounded-full px-2 py-0.5 text-[10px] font-bold"
              style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary)" }}
            >
              {i18n("memberProgrammingYourVersion")}
            </span>
          ) : null}
          {details ? (
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{details}</p>
          ) : null}
        </div>
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
          style={{
            background: isUnavailable ? "var(--border)" : `color-mix(in srgb, ${typeColor} 15%, transparent)`,
            color: isUnavailable ? "var(--dim)" : typeColor,
          }}
        >
          {classType.name}
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
