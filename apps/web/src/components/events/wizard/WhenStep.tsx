"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";

import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { DateInput, TimeInput } from "@/components/ui/DateInput";
import { Select } from "@/components/ui/Select";
import { timeZoneOptions, zoneLabel } from "@/lib/zoned-time";

import { DURATIONS } from "../events";
import { CheckRow, fieldClass } from "./fields";
import type { StepProps } from "./types";

/** «2 hours», «1 h 30 min» or «45 min». */
export function useDurationLabel() {
  const t = useTranslations("Events");
  return (minutes: number) =>
    minutes % 60 === 0
      ? t("hours", { count: minutes / 60 })
      : minutes > 60
        ? t("hoursMinutes", { hours: Math.floor(minutes / 60), minutes: minutes % 60 })
        : t("minutes", { count: minutes });
}

/**
 * Step 3: the day and time on the event's clock (ADR-179: the gym's, or
 * its own when it happens elsewhere), how long, and every week until a
 * date (only when creating; an edit changes one run's dates by scope).
 */
export function WhenStep({ form, set, context, problems, gym }: StepProps & { gym: { zone: string | null; confirmed: boolean } }) {
  const t = useTranslations("Events");
  const durationLabel = useDurationLabel();
  const [zoneOpen, setZoneOpen] = useState(false);
  const zone = form.timeZone ?? gym.zone;
  const zones = useMemo(() => timeZoneOptions(zone, gym.zone), [zone, gym.zone]);
  const away = Boolean(gym.zone && zone && zone !== gym.zone);
  const durations = DURATIONS.includes(form.durationMinutes) ? DURATIONS : [...DURATIONS, form.durationMinutes].sort((a, b) => a - b);
  const whenWrong = problems.includes("when") || problems.includes("past");

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-2">
        <Field label={t("fieldDate")}>
          <DateInput value={form.date} aria-invalid={whenWrong} onValueChange={(value) => set({ date: value })} className={fieldClass} style={inputStyle} />
        </Field>
        <Field label={t("fieldTime")}>
          <TimeInput value={form.time} aria-invalid={whenWrong} onValueChange={(value) => set({ time: value })} className={fieldClass} style={inputStyle} />
        </Field>
      </div>

      {zone ? (
        <div className="-mt-2 flex flex-col gap-2 text-xs" style={{ color: "var(--dim)" }}>
          <p className="flex flex-wrap items-center gap-x-2">
            <span>{t(away ? "zoneAway" : "zoneGym", { zone: zoneLabel(zone) })}</span>
            {!zoneOpen ? (
              <button type="button" className="min-h-11 font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setZoneOpen(true)}>
                {t("zoneChange")}
              </button>
            ) : null}
          </p>
          {!gym.confirmed && gym.zone ? (
            <p role="status" className="rounded-xl px-3 py-2" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--text)" }}>
              {t("zoneGymUnconfirmed", { zone: zoneLabel(gym.zone) })}
            </p>
          ) : null}
          {form.place.kind === "address" && !away && !zoneOpen ? <p>{t("zoneAwayHint")}</p> : null}
          {zoneOpen ? (
            <Field label={t("fieldTimeZone")}>
              <Select value={zone} onValueChange={(value) => set({ timeZone: value })} className={fieldClass} style={inputStyle}>
                {zones.map((option) => (
                  <option key={option} value={option}>
                    {option === gym.zone ? t("zoneGymOption", { zone: option }) : option}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
        </div>
      ) : null}

      <Field label={t("fieldDuration")}>
        <Select value={form.durationMinutes} onValueChange={(value) => set({ durationMinutes: Number(value) })} className={fieldClass} style={inputStyle}>
          {durations.map((minutes) => (
            <option key={minutes} value={minutes}>
              {durationLabel(minutes)}
            </option>
          ))}
        </Select>
      </Field>

      {context.editing ? null : (
        <div className="flex flex-col gap-2">
          <CheckRow checked={form.repeatWeekly} onChange={(checked) => set({ repeatWeekly: checked })}>
            {t("fieldRepeat")}
          </CheckRow>
          {form.repeatWeekly ? (
            <Field label={t("fieldRepeatUntil")}>
              <DateInput
                value={form.repeatUntil}
                min={form.date}
                aria-invalid={Boolean(form.repeatUntil) && problems.includes("repeat")}
                onValueChange={(value) => set({ repeatUntil: value })}
                className={fieldClass}
                style={inputStyle}
              />
            </Field>
          ) : null}
        </div>
      )}
    </div>
  );
}
