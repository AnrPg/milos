"use client";

import { FORMAT_FIELD_DEFS, type FormatParams, type SectionFormat } from "@/types/workout";

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
    { key: "start_reps", label: "Starting Reps", unit: "" },
    { key: "step_reps", label: "Added per Round", unit: "" },
    { key: "ladder_cap", label: "Cap", unit: "", optional: true },
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
    { key: "sets", label: "Sets", unit: "" },
  ],
  hrr: [
    { key: "effort_seconds", label: "Effort Duration", unit: "secs" },
    { key: "hr_zone", label: "Target HR Zone", unit: "Zone", optional: true },
  ],
  ladder_ascending: [
    { key: "start_reps", label: "Start Reps", unit: "" },
    { key: "step_reps", label: "Step", unit: "" },
    { key: "ladder_cap", label: "Cap", unit: "", optional: true },
  ],
  ladder_descending: [
    { key: "start_reps", label: "Start Reps", unit: "" },
    { key: "step_reps", label: "Step", unit: "" },
    { key: "min_reps", label: "Min Reps", unit: "" },
  ],
  pyramid: [
    { key: "peak_reps", label: "Peak Reps", unit: "" },
    { key: "step_reps", label: "Step", unit: "" },
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
        const value = params[label.key] ?? defaultValue;
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
            </div>
          </div>
        );
      })}
    </div>
  );
}
