"use client";




import {useUiTranslations} from "@/i18n/ui";
import { FORMAT_FIELD_DEFS, type FormatParams, type SectionFormat } from "@/types/workout";

import { TimeInput } from "./TimeInput";

type FieldLabel = {
  key: string;
  label: string;
  unit: string;
  optional?: boolean;
};

type Props = {
  format: SectionFormat;
  params: FormatParams;
  onChange: (params: FormatParams) => void;
};

export function FormatContextualFields({ format, params, onChange }: Props) {
  const i18n = useUiTranslations();
  const FORMAT_FIELD_LABELS: Partial<Record<SectionFormat, FieldLabel[]>> = {
    for_time: [{ key: "time_cap_seconds", label: i18n("timeCap42f692a"), unit: "secs", optional: true }],
    train_to_exhaustion: [{ key: "rest_seconds", label: i18n("restBetweenSets882ab69"), unit: "secs", optional: true }],
    kcal_target: [
      { key: "kcal_target", label: i18n("target61ad50a"), unit: "kcal" },
      { key: "time_cap_seconds", label: i18n("timeCap42f692a"), unit: "secs", optional: true },
    ],
    emom: [
      { key: "duration_seconds", label: i18n("totalDuration886186d"), unit: "secs" },
      { key: "interval_seconds", label: i18n("interval011efcd"), unit: "secs" },
    ],
    complex_emom: [
      { key: "duration_seconds", label: i18n("totalDuration886186d"), unit: "secs" },
      { key: "interval_seconds", label: i18n("interval011efcd"), unit: "secs" },
    ],
    even_odd: [{ key: "duration_seconds", label: i18n("totalDuration886186d"), unit: "secs" }],
    billat: [
      { key: "work_seconds", label: i18n("work00040ba"), unit: "secs" },
      { key: "rest_seconds", label: i18n("restb79e5f4"), unit: "secs" },
      { key: "cycles", label: i18n("cycles97f064a"), unit: "" },
    ],
    amrap: [{ key: "duration_seconds", label: i18n("duration1370004"), unit: "secs" }],
    edt: [
      { key: "duration_seconds", label: i18n("duration1370004"), unit: "secs" },
      { key: "pr_zone_rounds", label: i18n("prZoneRounds9799ad4"), unit: "", optional: true },
    ],
    death_by: [
      { key: "max_rounds", label: i18n("maxRoundsc005103"), unit: "rounds", optional: true },
    ],
    tabata: [
      { key: "work_seconds", label: i18n("work00040ba"), unit: "secs" },
      { key: "rest_seconds", label: i18n("restb79e5f4"), unit: "secs" },
      { key: "rounds", label: i18n("roundsceeac4a"), unit: "" },
    ],
    custom_hiit: [
      { key: "work_seconds", label: i18n("work00040ba"), unit: "secs" },
      { key: "rest_seconds", label: i18n("restb79e5f4"), unit: "secs" },
      { key: "rounds", label: i18n("roundsceeac4a"), unit: "" },
    ],
    cluster: [
      { key: "intra_rest_seconds", label: i18n("intraSetRest46c5759"), unit: "secs" },
    ],
    hrr: [
      { key: "hr_ceiling_bpm", label: i18n("hrCeilingStopWork3e9d698"), unit: "bpm" },
      { key: "hr_floor_bpm", label: i18n("hrFloorResumeWork82d77a0"), unit: "bpm" },
      { key: "cycles", label: i18n("cycles97f064a"), unit: "", optional: true },
      { key: "effort_cap_seconds", label: i18n("effortCapf1d0911"), unit: "secs", optional: true },
    ],
    ladder_ascending: [
      { key: "time_cap_seconds", label: i18n("timeCap42f692a"), unit: "secs", optional: true },
    ],
    ladder_descending: [
      { key: "min_reps", label: i18n("minReps96a7464"), unit: "", optional: true },
      { key: "time_cap_seconds", label: i18n("timeCap42f692a"), unit: "secs", optional: true },
    ],
    pyramid: [
      { key: "time_cap_seconds", label: i18n("timeCap42f692a"), unit: "secs", optional: true },
    ],
    rest: [{ key: "duration_seconds", label: i18n("duration1370004"), unit: "secs" }],
  };

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
                  {i18n("optional48a7b88")}
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
