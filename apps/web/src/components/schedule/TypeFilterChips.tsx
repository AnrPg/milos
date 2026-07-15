"use client";

import { useRef, useState } from "react";

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
  const detailsRef = useRef<HTMLDetailsElement>(null);
  const [pending, setPending] = useState(value);

  return (
    <div className="min-w-0 flex-1">
      <div className="hidden min-w-0 items-center gap-1.5 md:flex" aria-label="Filter by class type">
        <button
          aria-pressed={value.length === 0}
          className="shrink-0 rounded-full border px-2.5 py-1.5 text-xs font-semibold transition-colors"
          style={
            value.length === 0
              ? { background: "var(--text)", borderColor: "var(--text)", color: "var(--bg)" }
              : { background: "transparent", borderColor: "var(--border)", color: "var(--dim)" }
          }
          onClick={() => onChange([])}
          type="button"
        >
          All
        </button>

        {classTypes.map((type) => {
          const selected = value.includes(type.id);
          const color = classTypeColor(type);

          return (
            <button
              aria-pressed={selected}
              className="min-w-0 flex-1 truncate rounded-full border px-2 py-1.5 text-[11px] font-semibold transition-colors lg:px-2.5 lg:text-xs"
              key={type.id}
              onClick={() => onChange(toggle(value, type.id))}
              style={
                selected
                  ? { background: color, borderColor: color, color: "var(--bg)" }
                  : { background: "transparent", borderColor: "var(--border)", color: "var(--dim)" }
              }
              title={`${type.name}${type.archived_at ? " (archived)" : ""}`}
              type="button"
            >
              {type.name}
            </button>
          );
        })}
      </div>

      <details
        className="relative md:hidden"
        onToggle={(event) => {
          if (event.currentTarget.open) setPending(value);
        }}
        ref={detailsRef}
      >
        <summary
          className="flex cursor-pointer list-none items-center justify-between rounded-full px-4 py-2.5 text-sm font-semibold"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          <span>Class types</span>
          <span style={{ color: "var(--primary)" }}>{value.length === 0 ? "All" : `${value.length} selected`}</span>
        </summary>

        <div
          className="absolute left-0 right-0 top-full z-30 mt-2 rounded-[1.4rem] p-4 shadow-[0_20px_60px_rgba(0,0,0,0.55)]"
          style={{ background: "var(--panel)", border: "1px solid var(--border-strong)" }}
        >
          <div className="max-h-64 space-y-2 overflow-y-auto">
            {classTypes.map((type) => {
              const selected = pending.includes(type.id);
              return (
                <label
                  className="flex cursor-pointer items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-sm"
                  key={type.id}
                  style={{ background: selected ? "color-mix(in srgb, var(--primary) 10%, transparent)" : "var(--panel-muted)", color: "var(--text)" }}
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
              Clear
            </button>
            <button
              className="flex-1 rounded-full px-3 py-2 text-xs font-semibold"
              onClick={() => {
                onChange(pending);
                detailsRef.current?.removeAttribute("open");
              }}
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              type="button"
            >
              Apply
            </button>
          </div>
        </div>
      </details>
    </div>
  );
}
