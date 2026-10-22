"use client";

import { useUiTranslations } from "@/i18n/ui";
import React from "react";

import { FREE_TEXT_TIMER_FORMATS, type FreeTextTimerFormat, type FreeTextTimerPreset } from "@/lib/free-text-timer";
import type { SectionFormat } from "@/types/workout";

import { LONG_DURATION_PRESETS, SHORT_DURATION_PRESETS, TimeInput } from "./TimeInput";
import { Select } from "@/components/ui/Select";

type Props = {
  preset: FreeTextTimerPreset;
  formatLabels: Record<SectionFormat, string>;
  onChange: (preset: FreeTextTimerPreset) => void;
};

/** Format plus the few numbers each free-text timer format needs. */
export function FreeTextTimerFields({ preset, formatLabels, onChange }: Props) {
  const i18n = useUiTranslations();
  const set = (patch: Partial<FreeTextTimerPreset>) => onChange({ ...preset, ...patch });
  const { format } = preset;

  return (
    <div className="mt-4 space-y-3">
      <label className="block">
        <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {i18n("timerFormatLabel")}
        </span>
        <Select
          value={format}
          onValueChange={(value) => onChange({ format: value as FreeTextTimerFormat })}
          className="mt-2 w-full rounded-xl border px-3 py-2 text-sm"
          style={{ background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" }}
        >
          {FREE_TEXT_TIMER_FORMATS.map((item) => (
            <option key={item} value={item}>
              {formatLabels[item]}
            </option>
          ))}
        </Select>
      </label>

      {format === "amrap" || format === "for_time" ? (
        <Row label={format === "amrap" ? i18n("timerDurationLabel") : i18n("timeCap42f692a")}>
          <TimeInput
            value={preset.duration_seconds ?? null}
            onChange={(seconds) => set({ duration_seconds: seconds })}
            presets={LONG_DURATION_PRESETS}
            ariaLabel={format === "amrap" ? i18n("timerDurationLabel") : i18n("timeCap42f692a")}
          />
        </Row>
      ) : null}

      {format === "emom" || format === "death_by" ? (
        <Row label={i18n("timerIntervalLabel")}>
          <TimeInput
            value={preset.interval_seconds ?? 60}
            onChange={(seconds) => set({ interval_seconds: seconds })}
            presets={[30, 60, 90, 120, 180]}
            ariaLabel={i18n("timerIntervalLabel")}
          />
        </Row>
      ) : null}

      {format === "tabata" || format === "custom_hiit" ? (
        <>
          <Row label={i18n("workPhaseLabel")}>
            <TimeInput
              value={preset.work_seconds ?? 20}
              onChange={(seconds) => set({ work_seconds: seconds })}
              presets={SHORT_DURATION_PRESETS}
              ariaLabel={i18n("workPhaseLabel")}
            />
          </Row>
          <Row label={i18n("restPhaseLabel")}>
            <TimeInput
              value={preset.rest_seconds ?? (format === "tabata" ? 10 : null)}
              onChange={(seconds) => set({ rest_seconds: seconds })}
              presets={SHORT_DURATION_PRESETS}
              ariaLabel={i18n("restPhaseLabel")}
            />
          </Row>
        </>
      ) : null}

      {format === "emom" || format === "tabata" || format === "custom_hiit" || format === "death_by" ? (
        <Row label={i18n("roundsLabel")}>
          <input
            type="number"
            inputMode="numeric"
            min={1}
            aria-label={i18n("roundsLabel")}
            value={preset.rounds ?? (format === "death_by" ? "" : format === "emom" ? 10 : 8)}
            placeholder={format === "death_by" ? "∞" : undefined}
            onChange={(event) => {
              const value = Number(event.target.value);
              set({ rounds: Number.isFinite(value) && value > 0 ? Math.round(value) : null });
            }}
            className="w-24 rounded-lg px-2 py-1.5 text-end text-sm tabular-nums outline-none"
            style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
          />
        </Row>
      ) : null}
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3">
      <span className="pt-1.5 text-sm font-semibold" style={{ color: "var(--muted)" }}>
        {label}
      </span>
      {children}
    </div>
  );
}
