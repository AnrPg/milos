"use client";

import type { CSSProperties, InputHTMLAttributes } from "react";
import { useTranslations } from "next-intl";
import { IntegerInput } from "@/components/integer-input";
import { joinMinutes, splitMinutes } from "@/lib/duration-parts";

const fieldStyle: CSSProperties = { background: "var(--panel-muted)", border: "1px solid var(--border)" };

/**
 * ADR-226: a booking rule stored in minutes, entered as hours plus minutes.
 * null means "no limit"; the checkbox is offered only with `noLimitLabel`.
 */
export function DurationLimitField({
  label,
  help,
  value,
  min,
  max,
  fallback,
  noLimitLabel,
  onChange,
  testId,
  inputStyle = fieldStyle,
  inputProps,
}: {
  label: string;
  help?: string;
  value: number | null;
  min: number;
  max: number;
  /** The value restored when "no limit" is unticked. */
  fallback: number;
  noLimitLabel?: string;
  onChange: (value: number | null) => void;
  testId?: string;
  inputStyle?: CSSProperties;
  inputProps?: InputHTMLAttributes<HTMLInputElement>;
}) {
  const t = useTranslations("BookingRules");
  const parts = value === null ? null : splitMinutes(value);
  const maxHours = Math.floor(max / 60);

  return (
    <div className="text-sm font-semibold" data-testid={testId}>
      <span>{label}</span>
      <div className="mt-2 flex flex-wrap items-center gap-3">
        <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
          <IntegerInput
            {...inputProps}
            aria-label={t("hoursOf", { label })}
            data-testid={testId ? `${testId}-hours` : undefined}
            disabled={parts === null}
            min={0}
            max={maxHours}
            emptyValue={0}
            className="w-20 rounded-xl px-3 py-3 disabled:opacity-40"
            style={inputStyle}
            value={parts?.hours ?? null}
            onValueChange={(hours) => parts && onChange(joinMinutes({ ...parts, hours: hours ?? 0 }, min, max))}
          />
          {t("hours")}
        </label>
        <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
          <IntegerInput
            {...inputProps}
            aria-label={t("minutesOf", { label })}
            data-testid={testId ? `${testId}-minutes` : undefined}
            disabled={parts === null}
            min={0}
            max={59}
            emptyValue={0}
            className="w-20 rounded-xl px-3 py-3 disabled:opacity-40"
            style={inputStyle}
            value={parts?.minutes ?? null}
            onValueChange={(minutes) => parts && onChange(joinMinutes({ ...parts, minutes: minutes ?? 0 }, min, max))}
          />
          {t("minutes")}
        </label>
        {noLimitLabel ? (
          <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
            <input
              type="checkbox"
              data-testid={testId ? `${testId}-no-limit` : undefined}
              checked={value === null}
              onChange={(event) => onChange(event.target.checked ? null : fallback)}
            />
            {noLimitLabel}
          </label>
        ) : null}
      </div>
      {help ? <p className="mt-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{help}</p> : null}
    </div>
  );
}
