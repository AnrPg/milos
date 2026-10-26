"use client";

import { useTranslations } from "next-intl";

import type { SeriesEditScope } from "@/api/schedule";
import { DateInput } from "@/components/ui/DateInput";
import { Select } from "@/components/ui/Select";

/** The steps offered for "every nth class" (ADR-200 §3). */
export const SERIES_EVERY_OPTIONS = [1, 2, 3, 4, 5, 6, 7, 8] as const;

export function seriesScopeReady(scope: SeriesEditScope) {
  return scope.scope !== "range" || (Boolean(scope.from) && Boolean(scope.to) && scope.from <= scope.to);
}

/**
 * ADR-200: an edit, pause, cancel or delete of a class of a series reaches
 * this class, every upcoming class of the series (and the classes it creates
 * later), or the classes between two dates on the gym's clock; beyond this
 * class, optionally only every nth one counted from it.
 */
export function SeriesScopePicker({
  className,
  value,
  onChange,
  classDate,
}: {
  className: string;
  value: SeriesEditScope;
  onChange: (scope: SeriesEditScope) => void;
  classDate: string;
}) {
  const t = useTranslations("Schedule");
  const options: Array<{ scope: SeriesEditScope["scope"]; label: string }> = [
    { scope: "this", label: t("seriesScopeThis") },
    { scope: "all", label: t("seriesScopeAll") },
    { scope: "range", label: t("seriesScopeRange") },
  ];
  const every = value.every ?? 1;
  const range = value.scope === "range" ? value : { scope: "range" as const, from: classDate, to: classDate, every };

  return (
    <fieldset className={className} data-testid="series-scope">
      <legend className="text-sm font-semibold" style={{ color: "var(--muted)" }}>{t("seriesScopeLegend")}</legend>
      <div role="radiogroup" aria-label={t("seriesScopeLegend")} className="mt-2 flex flex-wrap gap-2">
        {options.map((option) => {
          const checked = value.scope === option.scope;
          return (
            <button
              key={option.scope}
              type="button"
              role="radio"
              aria-checked={checked}
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={checked ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
              onClick={() =>
                onChange(option.scope === "range" ? range : option.scope === "all" ? { scope: "all", every } : { scope: "this" })
              }
            >
              {option.label}
            </button>
          );
        })}
      </div>
      <p className="mt-2 text-xs leading-5" style={{ color: "var(--muted)" }}>{t(`seriesScopeHint_${value.scope}`)}</p>
      {value.scope === "range" ? (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <label className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("seriesScopeFrom")}
            <DateInput className="mt-2 w-full rounded-xl px-3 py-2" value={value.from} onValueChange={(from) => onChange({ ...value, from })} />
          </label>
          <label className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("seriesScopeTo")}
            <DateInput className="mt-2 w-full rounded-xl px-3 py-2" min={value.from} value={value.to} onValueChange={(to) => onChange({ ...value, to })} />
          </label>
        </div>
      ) : null}
      {value.scope !== "this" ? (
        <label className="mt-3 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {t("seriesEveryLabel")}
          <Select
            className="mt-2 w-full rounded-xl px-3 py-2"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={String(every)}
            onValueChange={(next) => onChange({ ...value, every: Number(next) })}
          >
            {SERIES_EVERY_OPTIONS.map((n) => (
              <option key={n} value={String(n)}>
                {n === 1 ? t("seriesEveryAll") : t("seriesEveryNth", { n })}
              </option>
            ))}
          </Select>
        </label>
      ) : null}
    </fieldset>
  );
}
