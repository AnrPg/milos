"use client";

import {
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type KeyboardEvent,
  type ReactNode,
} from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  addDays,
  addMonths,
  compareDays,
  firstDayOfWeek,
  formatTime,
  isoDay,
  monthGrid,
  parseIsoDay,
  parseTime,
  todayYmd,
  withinRange,
  type Ymd,
} from "@/lib/calendar-grid";

import { Popover } from "./Popover";

/**
 * The app's date and time pickers (ADR-182). They replace <input type="date">,
 * "time" and "datetime-local", whose popups the browser draws off-theme and,
 * on phones, partly off screen. Values keep the native formats
 * ("2026-10-22", "18:30", "2026-10-22T18:30"), so forms and APIs are unchanged.
 */

type TriggerProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "value" | "defaultValue" | "onChange" | "children" | "type" | "name" | "role" | "onBlur" | "placeholder"
> & {
  value?: string | null;
  defaultValue?: string;
  onValueChange?: (value: string) => void;
  /** Called when the picker closes, like a native field losing focus. */
  onBlur?: () => void;
  name?: string;
  required?: boolean;
  placeholder?: ReactNode;
};

function triggerStyle(style: CSSProperties | undefined): CSSProperties {
  return { background: "var(--control-bg)", border: "1px solid var(--control-border)", color: "var(--text)", ...style };
}

const panelStyle: CSSProperties = {
  background: "var(--panel)",
  border: "1px solid var(--border)",
  color: "var(--text)",
  boxShadow: "var(--shadow-lg)",
};

function Icon({ kind }: { kind: "calendar" | "clock" }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4 shrink-0" style={{ color: "var(--muted)" }}>
      {kind === "calendar" ? (
        <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
          <rect x="3" y="4.5" width="14" height="12.5" rx="2.5" />
          <path d="M3 8.5h14M7 2.75v3.5M13 2.75v3.5" />
        </g>
      ) : (
        <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
          <circle cx="10" cy="10" r="7" />
          <path d="M10 6v4l2.75 1.75" />
        </g>
      )}
    </svg>
  );
}

function useControllable(value: string | null | undefined, defaultValue: string | undefined, onValueChange?: (value: string) => void) {
  const [inner, setInner] = useState(defaultValue ?? "");
  const current = value === undefined ? inner : value ?? "";
  const set = (next: string) => {
    if (value === undefined) setInner(next);
    if (next !== current) onValueChange?.(next);
  };
  return [current, set] as const;
}

function HiddenFields({ name, required, value, onInvalid }: { name?: string; required?: boolean; value: string; onInvalid: () => void }) {
  return (
    <>
      {name ? <input type="hidden" name={name} value={value} /> : null}
      {required ? (
        <input
          aria-hidden="true"
          tabIndex={-1}
          required
          value={value}
          onChange={() => undefined}
          onInvalid={onInvalid}
          style={{ position: "absolute", width: 1, height: 1, opacity: 0, pointerEvents: "none" }}
        />
      ) : null}
    </>
  );
}

// ── Calendar ────────────────────────────────────────────────────────────────

type CalendarView = "days" | "months" | "years";

function navButtonClass() {
  return "grid h-9 w-9 place-items-center rounded-full text-lg leading-none transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)] disabled:opacity-30";
}

export function Calendar({
  value,
  onPick,
  min,
  max,
  onClear,
}: {
  value: string;
  onPick: (value: string) => void;
  min?: string;
  max?: string;
  /** Shown as «Clear» when the field may be empty. */
  onClear?: () => void;
}) {
  const t = useTranslations("Pickers");
  const locale = useLocale();
  const selected = parseIsoDay(value);
  const minDay = parseIsoDay(min);
  const maxDay = parseIsoDay(max);
  const today = todayYmd();
  const [focus, setFocus] = useState<Ymd>(() => selected ?? (withinRange(today, minDay, maxDay) ? today : minDay ?? maxDay ?? today));
  const [view, setView] = useState<CalendarView>("days");
  const gridRef = useRef<HTMLDivElement>(null);
  const weekStart = firstDayOfWeek(locale);
  const [focusOnRender, setFocusOnRender] = useState(true);

  useEffect(() => {
    if (!focusOnRender || view !== "days") return;
    const button = gridRef.current?.querySelector<HTMLButtonElement>(`[data-day="${isoDay(focus)}"]`);
    button?.focus({ preventScroll: true });
  }, [focus, view, focusOnRender]);

  const monthTitle = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(Date.UTC(focus.year, focus.month - 1, 1)),
  );
  const weekdayFormat = new Intl.DateTimeFormat(locale, { weekday: "narrow", timeZone: "UTC" });
  const weekdayLong = new Intl.DateTimeFormat(locale, { weekday: "long", timeZone: "UTC" });
  const dayLabel = new Intl.DateTimeFormat(locale, { dateStyle: "full", timeZone: "UTC" });
  const monthShort = new Intl.DateTimeFormat(locale, { month: "short", timeZone: "UTC" });
  const days = monthGrid(focus.year, focus.month, weekStart);
  const weekdays = days.slice(0, 7);

  function move(next: Ymd) {
    const clamped = minDay && compareDays(next, minDay) < 0 ? minDay : maxDay && compareDays(next, maxDay) > 0 ? maxDay : next;
    setFocusOnRender(true);
    setFocus(clamped);
  }

  function onGridKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
    const map: Record<string, () => Ymd> = {
      ArrowLeft: () => addDays(focus, rtl ? 1 : -1),
      ArrowRight: () => addDays(focus, rtl ? -1 : 1),
      ArrowUp: () => addDays(focus, -7),
      ArrowDown: () => addDays(focus, 7),
      PageUp: () => addMonths(focus, event.shiftKey ? -12 : -1),
      PageDown: () => addMonths(focus, event.shiftKey ? 12 : 1),
      Home: () => addDays(focus, -((weekdayOf(focus) - weekStart + 7) % 7)),
      End: () => addDays(focus, 6 - ((weekdayOf(focus) - weekStart + 7) % 7)),
    };
    const next = map[event.key];
    if (!next) return;
    event.preventDefault();
    move(next());
  }

  const prevMonthDisabled = Boolean(minDay && compareDays(addDays({ ...focus, day: 1 }, -1), minDay) < 0);
  const nextMonthDisabled = Boolean(maxDay && compareDays(addMonths({ ...focus, day: 1 }, 1), maxDay) > 0);
  const decade = Math.floor(focus.year / 12) * 12;

  return (
    <div className="w-[min(20.5rem,calc(100vw-2rem))] p-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <button
          type="button"
          className="rounded-full px-3 py-1.5 text-sm font-bold capitalize transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)]"
          aria-label={t("chooseMonthYear")}
          onClick={() => {
            setFocusOnRender(false);
            setView(view === "days" ? "months" : view === "months" ? "years" : "days");
          }}
        >
          {view === "years" ? `${decade} – ${decade + 11}` : view === "months" ? focus.year : monthTitle} <span aria-hidden="true" style={{ color: "var(--muted)" }}>▾</span>
        </button>
        <div className="flex items-center gap-1">
          <button
            type="button"
            className={navButtonClass()}
            data-nav="previous"
            aria-label={view === "days" ? t("previousMonth") : view === "months" ? t("previousYear") : t("previousYears")}
            disabled={view === "days" && prevMonthDisabled}
            onClick={() => {
              setFocusOnRender(false);
              setFocus(addMonths(focus, view === "days" ? -1 : view === "months" ? -12 : -144));
            }}
          >
            <span aria-hidden="true" className="rtl:-scale-x-100">‹</span>
          </button>
          <button
            type="button"
            className={navButtonClass()}
            data-nav="next"
            aria-label={view === "days" ? t("nextMonth") : view === "months" ? t("nextYear") : t("nextYears")}
            disabled={view === "days" && nextMonthDisabled}
            onClick={() => {
              setFocusOnRender(false);
              setFocus(addMonths(focus, view === "days" ? 1 : view === "months" ? 12 : 144));
            }}
          >
            <span aria-hidden="true" className="rtl:-scale-x-100">›</span>
          </button>
        </div>
      </div>

      {view === "days" ? (
        <div ref={gridRef} role="grid" aria-label={monthTitle} onKeyDown={onGridKeyDown}>
          <div role="row" className="grid grid-cols-7">
            {weekdays.map((day) => {
              const date = new Date(Date.UTC(day.year, day.month - 1, day.day));
              return (
                <span key={isoDay(day)} role="columnheader" aria-label={weekdayLong.format(date)} className="grid h-8 place-items-center text-[11px] font-bold uppercase" style={{ color: "var(--dim)" }}>
                  {weekdayFormat.format(date)}
                </span>
              );
            })}
          </div>
          {Array.from({ length: 6 }, (_, week) => (
            <div role="row" key={week} className="grid grid-cols-7">
              {days.slice(week * 7, week * 7 + 7).map((day) => {
                const iso = isoDay(day);
                const outside = day.month !== focus.month;
                const isSelected = Boolean(selected && compareDays(day, selected) === 0);
                const isToday = compareDays(day, today) === 0;
                const isFocus = compareDays(day, focus) === 0;
                const enabled = withinRange(day, minDay, maxDay);
                return (
                  <span role="gridcell" key={iso} aria-selected={isSelected}>
                    <button
                      type="button"
                      data-day={iso}
                      tabIndex={isFocus ? 0 : -1}
                      disabled={!enabled}
                      aria-label={dayLabel.format(new Date(Date.UTC(day.year, day.month - 1, day.day)))}
                      aria-current={isToday ? "date" : undefined}
                      onClick={() => onPick(iso)}
                      className="mx-auto grid h-10 w-10 place-items-center rounded-full text-sm tabular-nums transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)] disabled:pointer-events-none disabled:opacity-25"
                      style={{
                        background: isSelected ? "var(--primary)" : undefined,
                        color: isSelected ? "var(--primary-contrast)" : outside ? "var(--dim)" : "var(--text)",
                        fontWeight: isSelected || isToday ? 700 : undefined,
                        boxShadow: isToday && !isSelected ? "inset 0 0 0 2px var(--spark)" : undefined,
                      }}
                    >
                      {day.day}
                    </button>
                  </span>
                );
              })}
            </div>
          ))}
        </div>
      ) : view === "months" ? (
        <div className="grid grid-cols-3 gap-1.5">
          {Array.from({ length: 12 }, (_, index) => {
            const month = index + 1;
            const current = month === focus.month;
            return (
              <button
                key={month}
                type="button"
                onClick={() => {
                  setFocus({ year: focus.year, month, day: Math.min(focus.day, 28) });
                  setView("days");
                  setFocusOnRender(true);
                }}
                className="min-h-11 rounded-xl text-sm font-semibold capitalize transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)]"
                style={current ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { color: "var(--text)" }}
              >
                {monthShort.format(new Date(Date.UTC(2000, index, 1)))}
              </button>
            );
          })}
        </div>
      ) : (
        <div className="grid grid-cols-3 gap-1.5">
          {Array.from({ length: 12 }, (_, index) => {
            const year = decade + index;
            const current = year === focus.year;
            return (
              <button
                key={year}
                type="button"
                onClick={() => {
                  setFocus({ ...focus, year, day: Math.min(focus.day, 28) });
                  setView("months");
                }}
                className="min-h-11 rounded-xl text-sm font-semibold tabular-nums transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)]"
                style={current ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { color: "var(--text)" }}
              >
                {year}
              </button>
            );
          })}
        </div>
      )}

      <div className="mt-2 flex items-center justify-between gap-2 border-t pt-2" style={{ borderColor: "var(--border)" }}>
        {onClear ? (
          <button type="button" onClick={onClear} className="rounded-full px-3 py-1.5 text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("clear")}
          </button>
        ) : (
          <span />
        )}
        <button
          type="button"
          disabled={!withinRange(today, minDay, maxDay)}
          onClick={() => onPick(isoDay(today))}
          className="rounded-full px-3 py-1.5 text-sm font-semibold disabled:opacity-40"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
        >
          {t("today")}
        </button>
      </div>
    </div>
  );
}

function weekdayOf(date: Ymd) {
  return new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay();
}

// ── DateInput ───────────────────────────────────────────────────────────────

export type DateInputProps = TriggerProps & { min?: string; max?: string };

export function DateInput({
  value,
  defaultValue,
  onValueChange,
  onBlur,
  name,
  required,
  disabled,
  min,
  max,
  placeholder,
  className = "",
  style,
  id,
  onClick,
  ...rest
}: DateInputProps) {
  const t = useTranslations("Pickers");
  const locale = useLocale();
  const [current, set] = useControllable(value, defaultValue, onValueChange);
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const autoId = useId();
  const parsed = parseIsoDay(current);
  const shown = parsed
    ? new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(Date.UTC(parsed.year, parsed.month - 1, parsed.day)))
    : null;

  function close() {
    setOpen(false);
    triggerRef.current?.focus();
    onBlur?.();
  }

  return (
    <>
      <button
        {...rest}
        ref={triggerRef}
        id={id ?? `date-${autoId}`}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        disabled={disabled}
        data-value={current}
        onClick={(event) => {
          onClick?.(event);
          if (!event.defaultPrevented) setOpen((was) => !was);
        }}
        className={`inline-flex min-w-0 items-center justify-between gap-2 text-start tabular-nums disabled:cursor-not-allowed disabled:opacity-60 ${className}`}
        style={triggerStyle(style)}
      >
        <span className="min-w-0 flex-1 truncate" style={shown ? undefined : { color: "var(--placeholder)" }}>
          {shown ?? placeholder ?? t("chooseDate")}
        </span>
        <Icon kind="calendar" />
      </button>
      <HiddenFields name={name} required={required} value={parsed ? current : ""} onInvalid={() => triggerRef.current?.focus()} />
      <Popover
        anchorRef={triggerRef}
        open={open}
        onClose={() => {
          setOpen(false);
          onBlur?.();
        }}
        role="dialog"
        ariaLabel={t("chooseDate")}
        className="rounded-2xl"
        style={panelStyle}
      >
        <Calendar
          value={current}
          min={min}
          max={max}
          onPick={(next) => {
            set(next);
            close();
          }}
          onClear={
            required
              ? undefined
              : () => {
                  set("");
                  close();
                }
          }
        />
      </Popover>
    </>
  );
}

// ── TimeInput ───────────────────────────────────────────────────────────────

function TimeColumns({
  value,
  stepMinutes,
  onPick,
  onDone,
}: {
  value: string;
  stepMinutes: number;
  onPick: (value: string) => void;
  onDone: () => void;
}) {
  const t = useTranslations("Pickers");
  const parsed = parseTime(value);
  const hour = parsed?.hour ?? null;
  const minute = parsed?.minute ?? null;
  const minutes = Array.from({ length: Math.ceil(60 / stepMinutes) }, (_, index) => index * stepMinutes);
  if (minute !== null && !minutes.includes(minute)) {
    minutes.push(minute);
    minutes.sort((a, b) => a - b);
  }
  const hoursRef = useRef<HTMLDivElement>(null);
  const minutesRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    hoursRef.current?.querySelector<HTMLElement>("[aria-selected='true']")?.scrollIntoView?.({ block: "center" });
    minutesRef.current?.querySelector<HTMLElement>("[aria-selected='true']")?.scrollIntoView?.({ block: "center" });
    (hoursRef.current?.querySelector<HTMLElement>("[aria-selected='true']") ?? hoursRef.current?.querySelector<HTMLElement>("button"))?.focus({
      preventScroll: true,
    });
  }, []);

  function column(
    ref: typeof hoursRef,
    label: string,
    values: number[],
    selected: number | null,
    pick: (next: number) => void,
  ) {
    return (
      <div className="flex min-w-0 flex-1 flex-col">
        <span className="pb-1 text-center text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
          {label}
        </span>
        <div ref={ref} role="listbox" aria-label={label} className="max-h-56 overflow-y-auto overscroll-contain rounded-xl p-0.5" style={{ background: "var(--panel-muted)" }}>
          {values.map((entry) => {
            const isSelected = entry === selected;
            return (
              <button
                key={entry}
                type="button"
                role="option"
                aria-selected={isSelected}
                onClick={() => pick(entry)}
                onKeyDown={(event) => {
                  if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
                  event.preventDefault();
                  const sibling = (event.key === "ArrowDown" ? event.currentTarget.nextElementSibling : event.currentTarget.previousElementSibling) as HTMLElement | null;
                  sibling?.focus();
                }}
                className="block min-h-10 w-full rounded-lg text-center text-sm tabular-nums transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)]"
                style={isSelected ? { background: "var(--primary)", color: "var(--primary-contrast)", fontWeight: 700 } : { color: "var(--text)" }}
              >
                {String(entry).padStart(2, "0")}
              </button>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <div className="w-[min(14rem,calc(100vw-2rem))] p-3">
      <div className="flex gap-2">
        {column(hoursRef, t("hours"), Array.from({ length: 24 }, (_, index) => index), hour, (next) => onPick(formatTime(next, minute ?? 0)))}
        {column(minutesRef, t("minutes"), minutes, minute, (next) => onPick(formatTime(hour ?? 0, next)))}
      </div>
      <div className="mt-2 flex justify-end border-t pt-2" style={{ borderColor: "var(--border)" }}>
        <button type="button" onClick={onDone} className="rounded-full px-4 py-1.5 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("done")}
        </button>
      </div>
    </div>
  );
}

export type TimeInputProps = TriggerProps & {
  /** Seconds between choices, as on a native time field (300 = every 5 minutes). */
  step?: number;
};

export function TimeInput({
  value,
  defaultValue,
  onValueChange,
  onBlur,
  name,
  required,
  disabled,
  step,
  placeholder,
  className = "",
  style,
  id,
  onClick,
  ...rest
}: TimeInputProps) {
  const t = useTranslations("Pickers");
  const [current, set] = useControllable(value, defaultValue, onValueChange);
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const autoId = useId();
  const parsed = parseTime(current);
  const stepMinutes = Math.max(1, Math.round((step && step >= 60 ? step : 300) / 60));

  function finish() {
    setOpen(false);
    triggerRef.current?.focus();
    onBlur?.();
  }

  return (
    <>
      <button
        {...rest}
        ref={triggerRef}
        id={id ?? `time-${autoId}`}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        disabled={disabled}
        data-value={current}
        onClick={(event) => {
          onClick?.(event);
          if (!event.defaultPrevented) setOpen((was) => !was);
        }}
        className={`inline-flex min-w-0 items-center justify-between gap-2 text-start tabular-nums disabled:cursor-not-allowed disabled:opacity-60 ${className}`}
        style={triggerStyle(style)}
      >
        <span className="min-w-0 flex-1 truncate" style={parsed ? undefined : { color: "var(--placeholder)" }}>
          {parsed ? formatTime(parsed.hour, parsed.minute) : placeholder ?? "––:––"}
        </span>
        <Icon kind="clock" />
      </button>
      <HiddenFields name={name} required={required} value={parsed ? current : ""} onInvalid={() => triggerRef.current?.focus()} />
      <Popover
        anchorRef={triggerRef}
        open={open}
        onClose={() => {
          setOpen(false);
          onBlur?.();
        }}
        role="dialog"
        ariaLabel={t("chooseTime")}
        className="rounded-2xl"
        style={panelStyle}
      >
        <TimeColumns value={current} stepMinutes={stepMinutes} onPick={set} onDone={finish} />
      </Popover>
    </>
  );
}

// ── DateTimeInput ───────────────────────────────────────────────────────────

export type DateTimeInputProps = Omit<TriggerProps, "onClick"> & {
  min?: string;
  max?: string;
  step?: number;
  /** Classes for the wrapper around the two fields. */
  wrapperClassName?: string;
};

/** A day and a time side by side; the value is "YYYY-MM-DDTHH:MM" like datetime-local. */
export function DateTimeInput({
  value,
  defaultValue,
  onValueChange,
  onBlur,
  name,
  required,
  disabled,
  min,
  max,
  step,
  className = "",
  style,
  wrapperClassName = "",
  id,
  ...rest
}: DateTimeInputProps) {
  const [current, set] = useControllable(value, defaultValue, onValueChange);
  const [day = "", time = ""] = current.split("T");
  const [draftDay, setDraftDay] = useState(day);
  const [draftTime, setDraftTime] = useState(time.slice(0, 5));
  const shownDay = day || draftDay;
  const shownTime = time.slice(0, 5) || draftTime;

  function commit(nextDay: string, nextTime: string) {
    setDraftDay(nextDay);
    setDraftTime(nextTime);
    if (!nextDay) set("");
    else if (nextTime) set(`${nextDay}T${nextTime}`);
  }

  return (
    <div className={`flex min-w-0 gap-2 ${wrapperClassName}`}>
      <DateInput
        {...rest}
        id={id}
        value={shownDay}
        onValueChange={(next) => commit(next, shownTime || "09:00")}
        onBlur={onBlur}
        min={min?.slice(0, 10)}
        max={max?.slice(0, 10)}
        required={required}
        disabled={disabled}
        className={`flex-[3] ${className}`}
        style={style}
      />
      <TimeInput
        aria-label={rest["aria-label"]}
        aria-invalid={rest["aria-invalid"]}
        aria-describedby={rest["aria-describedby"]}
        value={shownTime}
        onValueChange={(next) => commit(shownDay, next)}
        onBlur={onBlur}
        step={step}
        required={required}
        disabled={disabled}
        className={`flex-[2] ${className}`}
        style={style}
      />
      {name ? <input type="hidden" name={name} value={current} /> : null}
    </div>
  );
}
