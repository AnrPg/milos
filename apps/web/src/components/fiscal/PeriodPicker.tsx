"use client";

import { useTranslations } from "next-intl";

import { DateInput } from "@/components/ui/DateInput";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { monthRange, utcDay, yearRange } from "./documents-model";
import { Chip, hintStyle } from "./fiscal-ui";

export type PeriodChoice = "month" | "previousMonth" | "year" | "custom";
export type Period = { choice: PeriodChoice; from: string; to: string };

/** The period of a download: this month, last month, this year or from… to… */
export function periodFor(choice: PeriodChoice, today: string, custom: { from: string; to: string }): { from: string; to: string } {
  if (choice === "month") return monthRange(today);
  if (choice === "previousMonth") return monthRange(today, -1);
  if (choice === "year") return yearRange(today);
  return custom;
}

export function PeriodPicker({
  label,
  today,
  value,
  onChange,
  testId,
}: {
  label: string;
  today: string;
  value: Period;
  onChange: (period: Period) => void;
  testId: string;
}) {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const monthName = (offset: number) => {
    const text = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(utcDay(monthRange(today, offset).from));
    return text.charAt(0).toLocaleUpperCase(locale) + text.slice(1);
  };
  const choices: Array<[PeriodChoice, string]> = [
    ["month", monthName(0)],
    ["previousMonth", monthName(-1)],
    ["year", t("periodYear", { year: today.slice(0, 4) })],
    ["custom", t("periodCustom")],
  ];
  const pick = (choice: PeriodChoice) => onChange({ choice, ...periodFor(choice, today, { from: value.from, to: value.to }) });

  return (
    <fieldset className="grid gap-1.5" data-testid={testId}>
      <legend className="mb-1.5 text-xs font-bold" style={{ color: "var(--text-soft)" }}>{label}</legend>
      <div className="flex flex-wrap gap-1.5">
        {choices.map(([choice, text]) => (
          <Chip key={choice} on={value.choice === choice} onClick={() => pick(choice)} testId={`${testId}-${choice}`}>
            {text}
          </Chip>
        ))}
      </div>
      {value.choice === "custom" ? (
        <div className="grid grid-cols-2 gap-2">
          <label className="grid gap-1 text-xs" style={hintStyle}>
            {t("from")}
            <DateInput data-testid={`${testId}-from`} value={value.from} max={value.to} onValueChange={(from) => onChange({ ...value, from })} />
          </label>
          <label className="grid gap-1 text-xs" style={hintStyle}>
            {t("to")}
            <DateInput data-testid={`${testId}-to`} value={value.to} min={value.from} onValueChange={(to) => onChange({ ...value, to })} />
          </label>
        </div>
      ) : null}
    </fieldset>
  );
}
