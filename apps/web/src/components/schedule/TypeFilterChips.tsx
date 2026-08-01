"use client";


import { useState } from "react";

import { useTranslations } from "next-intl";

import type { ClassTypeRecord } from "@/api/schedule";
import { WORKOUT_TYPE_COLORS } from "@/lib/workout-colors";

type TypeFilterChipsProps = {
  classTypes: ClassTypeRecord[];
  value: string[];
  onChange: (value: string[]) => void;
};

function classTypeColor(type: ClassTypeRecord) {
  return WORKOUT_TYPE_COLORS[type.slug] ?? "var(--primary)";
}

function toggle(values: string[], id: string) {
  return values.includes(id) ? values.filter((value) => value !== id) : [...values, id];
}

export function TypeFilterChips({ classTypes, value, onChange }: TypeFilterChipsProps) {
  const [pending, setPending] = useState(value);
  const [open, setOpen] = useState(false);
  const [pinned, setPinned] = useState(false);
  const t = useTranslations("Schedule");

  if (classTypes.filter((type) => !type.archived_at).length <= 1) return null;

  return (
    <div
      className="relative min-w-0 flex-1"
      onMouseEnter={() => {
        setPending(value);
        setOpen(true);
      }}
      onMouseLeave={() => {
        if (!pinned) setOpen(false);
      }}
    >
      <button
        type="button"
        aria-expanded={open}
        className="flex w-full max-w-md items-center justify-between rounded-full px-4 py-2.5 text-sm font-semibold"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        onClick={() => {
          setPending(value);
          setPinned((current) => {
            const nextPinned = !current;
            setOpen(nextPinned || !open);
            return nextPinned;
          });
        }}
      >
        <span>{t("classTypes")}</span>
        <span style={{ color: "var(--primary)" }}>{value.length === 0 ? t("all") : t("selectedCount", { count: value.length })}</span>
      </button>

      {open ? (
        <div
          className="absolute start-0 top-full z-30 mt-2 w-full max-w-md rounded-[1.4rem] p-4 shadow-[0_20px_60px_rgba(0,0,0,0.55)]"
          style={{ background: "var(--panel)", border: "1px solid var(--border-strong)" }}
        >
          <div className="max-h-64 space-y-2 overflow-y-auto">
            <label
              className="flex cursor-pointer items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-sm"
              style={{ background: pending.length === 0 ? "color-mix(in srgb, var(--primary) 10%, transparent)" : "var(--panel-muted)", color: "var(--text)" }}
            >
              <span className="truncate">{t("all")}</span>
              <input checked={pending.length === 0} onChange={() => setPending([])} type="checkbox" />
            </label>
            {classTypes.map((type) => {
              const selected = pending.includes(type.id);
              const color = classTypeColor(type);
              return (
                <label
                  className="flex cursor-pointer items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-sm"
                  key={type.id}
                  style={{ background: selected ? `color-mix(in srgb, ${color} 12%, transparent)` : "var(--panel-muted)", color: "var(--text)" }}
                >
                  <span className="truncate">{type.name}</span>
                  <input
                    checked={selected}
                    onChange={() => setPending((current) => toggle(current, type.id))}
                    type="checkbox"
                  />
                </label>
              );
            })}
          </div>

          <div className="mt-4 flex gap-2">
            <button
              className="flex-1 rounded-full px-3 py-2 text-xs font-semibold"
              onClick={() => setPending([])}
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              type="button"
            >
              {t("clear")}
            </button>
            <button
              className="flex-1 rounded-full px-3 py-2 text-xs font-semibold"
              onClick={() => {
                onChange(pending);
                setPinned(false);
                setOpen(false);
              }}
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              type="button"
            >
              {t("apply")}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
