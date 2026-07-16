"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";

type InlineCellProps = {
  value: string;
  display?: string;
  type?: "text" | "number" | "date";
  onSave: (value: string) => void;
  placeholder?: string;
  dimmed?: boolean;
  warn?: boolean;
};

export function InlineCell({ value, display, type = "text", onSave, placeholder, dimmed, warn }: InlineCellProps) {
  
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (editing) inputRef.current?.focus();
  }, [editing]);

  function commit() {
    setEditing(false);
    if (draft !== value) onSave(draft);
  }

  function cancel() {
    setEditing(false);
    setDraft(value);
  }

  if (editing) {
    if (type === "date") {
      return (
        <InlineDateEditor
          value={draft}
          onCancel={cancel}
          onChange={setDraft}
          onCommit={commit}
          onSelect={(nextValue) => {
            setDraft(nextValue);
            setEditing(false);
            if (nextValue !== value) onSave(nextValue);
          }}
        />
      );
    }

    return (
      <input
        ref={inputRef}
        className="w-full rounded-[0.8rem] px-2 py-1 text-sm outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--primary)", color: "var(--text)", minWidth: "7rem" }}
        type={type}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") cancel();
        }}
      />
    );
  }

  const shown = display ?? value;

  return (
    <button
      className="rounded-[0.8rem] px-2 py-1 text-start text-sm transition-colors hover:opacity-80"
      style={{
        color: warn ? "var(--primary-strong)" : dimmed ? "var(--dim)" : "var(--text)",
        background: "transparent",
        borderBottom: "1px dashed var(--border)",
        minWidth: "7rem",
      }}
      onClick={() => {
        setDraft(value);
        setEditing(true);
      }}
      type="button"
    >
      {shown || <span style={{ color: "var(--dim)" }}>{placeholder ?? "—"}</span>}
    </button>
  );
}

function parseDateParts(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;

  const [, year, month, day] = match;
  return {
    year: Number(year),
    month: Number(month),
    day: Number(day),
  };
}

function dateKey(year: number, month: number, day: number) {
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function monthDays(year: number, month: number) {
  return new Date(year, month, 0).getDate();
}

function weekdayOffset(year: number, month: number) {
  return new Date(year, month - 1, 1).getDay();
}

function InlineDateEditor({
  value,
  onCancel,
  onChange,
  onCommit,
  onSelect,
}: {
  value: string;
  onCancel: () => void;
  onChange: (value: string) => void;
  onCommit: () => void;
  onSelect: (value: string) => void;
}) {
  const i18n = useUiTranslations();
  const inputRef = useRef<HTMLInputElement>(null);
  const today = new Date();
  const parsed = parseDateParts(value);
  const [visibleMonth, setVisibleMonth] = useState(() => ({
    year: parsed?.year ?? today.getFullYear(),
    month: parsed?.month ?? today.getMonth() + 1,
  }));
  const selectedKey = parsed ? dateKey(parsed.year, parsed.month, parsed.day) : "";
  const daysInMonth = monthDays(visibleMonth.year, visibleMonth.month);
  const leadingDays = weekdayOffset(visibleMonth.year, visibleMonth.month);
  const monthLabel = new Intl.DateTimeFormat(undefined, { month: "short", year: "numeric" }).format(
    new Date(visibleMonth.year, visibleMonth.month - 1, 1),
  );
  const weekdayLabels = Array.from({ length: 7 }, (_, index) =>
    new Intl.DateTimeFormat(undefined, { weekday: "narrow" }).format(new Date(2026, 5, index + 7)),
  );

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function shiftMonth(delta: number) {
    setVisibleMonth((current) => {
      const next = new Date(current.year, current.month - 1 + delta, 1);
      return { year: next.getFullYear(), month: next.getMonth() + 1 };
    });
  }

  function selectDay(day: number) {
    onSelect(dateKey(visibleMonth.year, visibleMonth.month, day));
  }

  return (
    <div className="relative min-w-[14rem]">
      <div
        className="flex items-center rounded-[0.8rem]"
        style={{ background: "var(--panel)", border: "1px solid var(--primary)", color: "var(--text)" }}
      >
        <input
          ref={inputRef}
          className="min-w-0 flex-1 bg-transparent px-2 py-1 text-sm outline-none"
          inputMode="numeric"
          onBlur={(event) => {
            if (!event.currentTarget.parentElement?.parentElement?.contains(event.relatedTarget as Node | null)) {
              onCommit();
            }
          }}
          onChange={(event) => onChange(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") onCommit();
            if (event.key === "Escape") onCancel();
          }}
          placeholder="yyyy-mm-dd"
          value={value}
        />
        <button
          aria-label={i18n("calendar4e44752")}
          className="px-2 py-1"
          onMouseDown={(event) => event.preventDefault()}
          style={{ color: "var(--primary)" }}
          type="button"
        >
          <svg aria-hidden="true" className="h-4 w-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24">
            <path d="M8 2v4" />
            <path d="M16 2v4" />
            <path d="M3 10h18" />
            <rect height="18" rx="2" width="18" x="3" y="4" />
          </svg>
        </button>
      </div>

      <div
        className="absolute start-0 top-full z-50 mt-2 w-64 rounded-[1.2rem] p-3 shadow-[0_20px_60px_rgba(0,0,0,0.45)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
      >
        <div className="flex items-center justify-between">
          <button
            className="rounded-full px-2 py-1 text-sm font-bold"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => shiftMonth(-1)}
            style={{ color: "var(--primary)" }}
            type="button"
          >
            ‹
          </button>
          <p className="text-sm font-semibold">{monthLabel}</p>
          <button
            className="rounded-full px-2 py-1 text-sm font-bold"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => shiftMonth(1)}
            style={{ color: "var(--primary)" }}
            type="button"
          >
            ›
          </button>
        </div>
        <div className="mt-3 grid grid-cols-7 gap-1 text-center text-[10px] font-semibold uppercase" style={{ color: "var(--dim)" }}>
          {weekdayLabels.map((day, index) => (
            <span key={`${day}-${index}`}>{day}</span>
          ))}
        </div>
        <div className="mt-1 grid grid-cols-7 gap-1">
          {Array.from({ length: leadingDays }, (_, index) => (
            <span key={`empty-${index}`} />
          ))}
          {Array.from({ length: daysInMonth }, (_, index) => {
            const day = index + 1;
            const key = dateKey(visibleMonth.year, visibleMonth.month, day);
            const selected = key === selectedKey;
            return (
              <button
                key={key}
                className="flex h-7 items-center justify-center rounded-full text-xs font-semibold"
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => selectDay(day)}
                style={{
                  background: selected ? "var(--primary)" : "transparent",
                  color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
                }}
                type="button"
              >
                {day}
              </button>
            );
          })}
        </div>
        <div className="mt-3 flex justify-between">
          <button
            className="text-xs font-semibold"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => onSelect("")}
            style={{ color: "var(--dim)" }}
            type="button"
          >
            {i18n("clearFilters4122267")}
          </button>
          <button
            className="text-xs font-semibold"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => {
              const now = new Date();
              onSelect(dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate()));
              setVisibleMonth({ year: now.getFullYear(), month: now.getMonth() + 1 });
            }}
            style={{ color: "var(--primary)" }}
            type="button"
          >
            {i18n("today24345a1")}
          </button>
        </div>
      </div>
    </div>
  );
}

export function InlineToggle({
  value,
  options,
  onSave,
}: {
  value: string;
  options: Array<{ value: string; label: string; accent?: boolean }>;
  onSave: (value: string) => void;
}) {
  const i18n = useUiTranslations();
  const current = options.find((o) => o.value === value) ?? options[0];
  const next = options[(options.indexOf(current) + 1) % options.length];

  return (
    <button
      className="rounded-full px-3 py-1 text-xs font-semibold"
      style={{
        background: current.accent ? "color-mix(in srgb, var(--primary) 12%, transparent)" : "var(--border)",
        color: current.accent ? "var(--primary)" : "var(--text-soft)",
        border: current.accent ? "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" : "1px solid var(--border-strong)",
      }}
      onClick={() => onSave(next.value)}
      type="button"
      title={i18n("clickToSet1c43780") + (next.label)}
    >
      {current.label}
    </button>
  );
}
