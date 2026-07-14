"use client";

import type { TrainingType } from "@/api/schedule";
import { WORKOUT_TYPE_COLORS } from "@/lib/workout-colors";

const TYPES: Array<{ value: TrainingType; label: string }> = [
  { value: "crossfit", label: "CrossFit" },
  { value: "strength", label: "Strength" },
  { value: "gymnastics", label: "Gymnastics" },
  { value: "aerobics", label: "Aerobics" },
  { value: "flexibility", label: "Flexibility" },
  { value: "recovery", label: "Recovery" },
];

type TypeFilterChipsProps = {
  value: TrainingType | null;
  onChange: (value: TrainingType | null) => void;
};

export function TypeFilterChips({ value, onChange }: TypeFilterChipsProps) {
  return (
    <div className="flex flex-wrap gap-2">
      <button
        className="rounded-full border px-4 py-2 text-sm font-semibold transition-colors"
        style={
          value === null
            ? { background: "var(--text)", borderColor: "var(--text)", color: "var(--bg)" }
            : { background: "transparent", borderColor: "var(--border)", color: "var(--dim)" }
        }
        onClick={() => onChange(null)}
        type="button"
      >
        All
      </button>

      {TYPES.map((type) => {
        const color = WORKOUT_TYPE_COLORS[type.value] ?? "var(--primary)";
        return (
          <button
            key={type.value}
            className="rounded-full border px-4 py-2 text-sm font-semibold transition-colors"
            style={
              value === type.value
                ? { background: color, borderColor: color, color: "var(--bg)" }
                : { background: "transparent", borderColor: "var(--border)", color: "var(--dim)" }
            }
            onClick={() => onChange(type.value === value ? null : type.value)}
            type="button"
          >
            {type.label}
          </button>
        );
      })}
    </div>
  );
}
