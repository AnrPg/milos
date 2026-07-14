"use client";

import { FORMAT_FIELD_DEFS, type FormatParams, type SectionFormat } from "@/types/workout";

import { TimeInput } from "./TimeInput";

type FieldLabel = {
  key: string;
  label: string;
  unit: string;
  optional?: boolean;
};

const FORMAT_FIELD_LABELS: Partial<Record<SectionFormat, FieldLabel[]>> = {
  for_time: [{ key: "time_cap_seconds", label: "Time Cap", unit: "secs", optional: true }],
  train_to_exhaustion: [{ key: "rest_seconds", label: "Rest between sets", unit: "secs", optional: true }],
  kcal_target: [
    { key: "kcal_target", label: "Target", unit: "kcal" },
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", optional: true },
  ],
  emom: [
    { key: "duration_seconds", label: "Total Duration", unit: "secs" },
    { key: "interval_seconds", label: "Interval", unit: "secs" },
  ],
  complex_emom: [
    { key: "duration_seconds", label: "Total Duration", unit: "secs" },
    { key: "interval_seconds", label: "Interval", unit: "secs" },
  ],
  even_odd: [{ key: "duration_seconds", label: "Total Duration", unit: "secs" }],
  billat: [
    { key: "work_seconds", label: "Work", unit: "secs" },
    { key: "rest_seconds", label: "Rest", unit: "secs" },
    { key: "cycles", label: "Cycles", unit: "" },
  ],
  amrap: [{ key: "duration_seconds", label: "Duration", unit: "secs" }],
  edt: [
    { key: "duration_seconds", label: "Duration", unit: "secs" },
    { key: "pr_zone_rounds", label: "PR Zone Rounds", unit: "", optional: true },
  ],
  death_by: [
    { key: "max_rounds", label: "Max Rounds", unit: "rounds", optional: true },
  ],
  tabata: [
    { key: "work_seconds", label: "Work", unit: "secs" },
    { key: "rest_seconds", label: "Rest", unit: "secs" },
    { key: "rounds", label: "Rounds", unit: "" },
  ],
  custom_hiit: [
    { key: "work_seconds", label: "Work", unit: "secs" },
    { key: "rest_seconds", label: "Rest", unit: "secs" },
    { key: "rounds", label: "Rounds", unit: "" },
  ],
  cluster: [
    { key: "intra_rest_seconds", label: "Intra-set Rest", unit: "secs" },
  ],
  hrr: [
    { key: "hr_ceiling_bpm", label: "HR Ceiling (stop work)", unit: "bpm" },
    { key: "hr_floor_bpm", label: "HR Floor (resume work)", unit: "bpm" },
    { key: "cycles", label: "Cycles", unit: "", optional: true },
    { key: "effort_cap_seconds", label: "Effort Cap", unit: "secs", optional: true },
  ],
  ladder_ascending: [
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", optional: true },
  ],
  ladder_descending: [
    { key: "min_reps", label: "Min Reps", unit: "", optional: true },
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", optional: true },
  ],
  pyramid: [
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", optional: true },
  ],
  rest: [{ key: "duration_seconds", label: "Duration", unit: "secs" }],
};

type Props = {
  format: SectionFormat;
  params: FormatParams;
  onChange: (params: FormatParams) => void;
};

export function FormatContextualFields({ format, params, onChange }: Props) {
  const labelDefs = FORMAT_FIELD_LABELS[format];
  const fieldDefs = FORMAT_FIELD_DEFS[format];

  if (!labelDefs || labelDefs.length === 0) return null;

  function handleChange(key: string, raw: string) {
    const value = Number.parseInt(raw, 10);
    onChange({ ...params, [key]: Number.isNaN(value) ? null : value });
  }

  return (
    <div className="mt-2 flex flex-col gap-3">
      {labelDefs.map((label) => {
        const defaultValue = fieldDefs?.find((f) => f.key === label.key)?.defaultValue ?? 0;
        const hasValue = Object.prototype.hasOwnProperty.call(params, label.key);
        const value = hasValue ? params[label.key] : defaultValue;
        const field = { ...label, defaultValue };

        return (
          <div key={field.key} className="flex items-center justify-between gap-2">
            <label className="shrink-0 text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
              {field.label}
              {field.optional ? (
                <span className="ml-1 font-normal italic normal-case" style={{ color: "var(--dim)" }}>
                  optional
                </span>
              ) : null}
            </label>

            <div className="flex items-center gap-2">
              {field.unit === "secs" ? (
                <TimeInput
                  value={typeof value === "number" ? value : null}
                  onChange={(secs) => onChange({ ...params, [field.key]: secs })}
                />
              ) : (
                <>
                  <input
                    type="number"
                    value={value ?? ""}
                    onChange={(event) => handleChange(field.key, event.target.value)}
                    className="w-20 rounded-lg px-2 py-1 text-right text-sm outline-none"
                    style={{
                      background: "var(--bg)",
                      border: "1px solid var(--dim)",
                      color: "var(--text)",
                    }}
                  />
                  {field.unit ? (
                    <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>
                      {field.unit}
                    </span>
                  ) : null}
                </>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
