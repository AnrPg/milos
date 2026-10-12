"use client";

import { useId, useMemo, useState, type ReactNode } from "react";

import type { FacilityLocation } from "@/api/facility";
import type { FinanceRecord } from "@/api/finance";
import type { ClassTypeRecord } from "@/api/schedule";
import type { UiTranslator } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import {
  equal,
  fieldLabelKey,
  fieldLocks,
  fieldSpec,
  groupSizeForFormat,
  isFieldLocked,
  isPartLocked,
  lockReasonKey,
  memberSummary,
  moduleEnabled,
  presetFor,
  priceCents,
  sectionLabelKey,
  typeLabelKey,
  type CatalogField,
  type CatalogType,
  type ClassTypeLimit,
  type DurationValue,
  type PackageCatalog,
  type PackageDraft,
  type QuotaPeriod,
  type QuotaValue,
  type SummaryNames,
} from "./package-catalog";
import { useStaffCoaches, type CoachOption } from "./use-package-authoring";

export type FieldContext = {
  classTypes: ClassTypeRecord[];
  packages: FinanceRecord[];
  locations: FacilityLocation[];
};

const inputClass = "w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none";
const inputStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };

export function useT(): UiTranslator {
  const i18n = useUiTranslations();
  return i18n as unknown as UiTranslator;
}

export function money(locale: string, cents: number | null) {
  if (cents === null) return "";
  return new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" }).format(cents / 100);
}

export function FieldShell({
  label,
  hint,
  error,
  changed,
  onReset,
  children,
  htmlFor,
}: {
  label: string;
  hint?: string;
  error?: string;
  changed?: boolean;
  onReset?: () => void;
  children: ReactNode;
  htmlFor?: string;
}) {
  const t = useT();
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-3">
        <label htmlFor={htmlFor} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {label}
        </label>
        {changed && onReset ? (
          <button
            type="button"
            onClick={onReset}
            className="rounded-full px-2.5 py-1 text-xs font-semibold"
            style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
            title={t("pkgResetFieldHint")}
          >
            {t("pkgChanged")} ↺
          </button>
        ) : null}
      </div>
      {children}
      {hint ? <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      {error ? <p className="text-xs font-semibold" role="alert" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className="relative inline-flex h-7 w-12 shrink-0 items-center rounded-full transition-colors disabled:opacity-60"
      style={{ background: checked ? "var(--primary)" : "var(--border)" }}
    >
      <span
        className="inline-block h-5 w-5 rounded-full transition-transform"
        style={{ background: "var(--bg)", transform: checked ? "translateX(1.55rem)" : "translateX(0.25rem)" }}
      />
    </button>
  );
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  label: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-1 rounded-2xl p-1" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={value === option.value}
          onClick={() => onChange(option.value)}
          className="min-h-[2.5rem] flex-1 rounded-xl px-3 text-sm font-semibold"
          style={{
            background: value === option.value ? "var(--panel)" : "transparent",
            color: value === option.value ? "var(--text)" : "var(--dim)",
            boxShadow: value === option.value ? "0 1px 3px rgba(0,0,0,0.12)" : "none",
          }}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function Stepper({
  value,
  onChange,
  min = 0,
  max = 10000,
  label,
  suffix,
}: {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  label: string;
  suffix?: string;
}) {
  const clamp = (next: number) => Math.min(max, Math.max(min, next));
  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        aria-label={`${label} −`}
        onClick={() => onChange(clamp(value - 1))}
        className="h-11 w-11 shrink-0 rounded-xl text-lg font-semibold"
        style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        −
      </button>
      <input
        aria-label={label}
        inputMode="numeric"
        className={inputClass + " h-11 max-w-[7rem] text-center"}
        style={inputStyle}
        value={String(value)}
        onChange={(event) => {
          const next = Number(event.target.value.replace(/\D/g, ""));
          if (Number.isFinite(next)) onChange(clamp(next));
        }}
      />
      <button
        type="button"
        aria-label={`${label} +`}
        onClick={() => onChange(clamp(value + 1))}
        className="h-11 w-11 shrink-0 rounded-xl text-lg font-semibold"
        style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        +
      </button>
      {suffix ? <span className="text-sm" style={{ color: "var(--dim)" }}>{suffix}</span> : null}
    </div>
  );
}

export function LockedValue({ text, reason }: { text: string; reason: string }) {
  return (
    <div className="flex items-start gap-2 rounded-xl px-3 py-2 text-sm" style={{ background: "var(--bg-soft)", border: "1px dashed var(--border)", color: "var(--text-soft)" }}>
      <span aria-hidden="true">🔒</span>
      <div>
        <p className="font-semibold">{text}</p>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{reason}</p>
      </div>
    </div>
  );
}

export function PeriodSelect({
  value,
  onChange,
  periods,
  label,
}: {
  value: QuotaPeriod;
  onChange: (value: QuotaPeriod) => void;
  periods: QuotaPeriod[];
  label: string;
}) {
  const t = useT();
  return (
    <select aria-label={label} className={inputClass + " h-11"} style={inputStyle} value={value} onChange={(event) => onChange(event.target.value as QuotaPeriod)}>
      {periods.map((period) => (
        <option key={period} value={period}>{t(`pkgPeriod_${period}`)}</option>
      ))}
    </select>
  );
}

/** Limit + reset period for a quota; respects partial locks. */
export function QuotaControl({
  type,
  fieldKey,
  value,
  onChange,
  label,
  unitLabel,
}: {
  type: CatalogType;
  fieldKey: string;
  value: QuotaValue;
  onChange: (value: QuotaValue) => void;
  label: string;
  unitLabel: string;
}) {
  const t = useT();
  const limitLocked = isPartLocked(type, fieldKey, "limit");
  const periodLocked = isPartLocked(type, fieldKey, "period");
  const limited = value.limit !== "unlimited" && value.limit !== 0;
  const none = value.limit === 0;
  const limitRequired =
    (type.key === "class_pack" && fieldKey === "group_classes.visits") ||
    (type.key === "pt_pack" && fieldKey === "personal_training.sessions");
  // Perks and coaching extras start at none: they are opt-in (ADR-097, ADR-098).
  const allowNone = ["perks.guest_passes", "online_coaching.form_reviews", "personal_training.sessions"].includes(fieldKey);

  return (
    <div className="space-y-3">
      {limitLocked ? null : limitRequired ? null : (
        <Segmented
          label={label}
          value={none ? "none" : limited ? "limited" : "unlimited"}
          options={[
            ...(allowNone ? [{ value: "none" as const, label: t("pkgNone") }] : []),
            { value: "unlimited", label: t("pkgUnlimited") },
            { value: "limited", label: t("pkgLimited") },
          ]}
          onChange={(mode) => onChange({ ...value, limit: mode === "none" ? 0 : mode === "unlimited" ? "unlimited" : allowNone ? 2 : 8 })}
        />
      )}
      {limited && !limitLocked ? (
        <div className="flex flex-wrap items-center gap-3">
          <Stepper
            label={label}
            value={value.limit as number}
            min={1}
            onChange={(limit) => onChange({ ...value, limit })}
            suffix={unitLabel}
          />
          {periodLocked ? (
            <span className="text-sm" style={{ color: "var(--dim)" }}>{t("pkgPeriodWhole")}</span>
          ) : (
            <div className="min-w-[10rem] flex-1">
              <PeriodSelect
                label={t("pkgResetsEvery")}
                value={value.period}
                periods={["calendar_week", "calendar_month"]}
                onChange={(period) => onChange({ ...value, period })}
              />
            </div>
          )}
        </div>
      ) : null}
      {!limited && !none && !periodLocked ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("pkgUnlimitedHint")}</p>
      ) : null}
    </div>
  );
}

export function ClassTypeScope({
  value,
  onChange,
  classTypes,
}: {
  value: unknown;
  onChange: (value: "all" | string[]) => void;
  classTypes: ClassTypeRecord[];
}) {
  const t = useT();
  return (
    <IdScope
      value={value}
      onChange={onChange}
      items={classTypes}
      label={t("pkgFieldGroupClassesClassTypes")}
      allLabel={t("pkgClassTypesAll")}
      someLabel={t("pkgClassTypesSome")}
      emptyText={t("pkgNoClassTypesYet")}
    />
  );
}

export function LocationScope({
  value,
  onChange,
  locations,
}: {
  value: unknown;
  onChange: (value: "all" | string[]) => void;
  locations: FacilityLocation[];
}) {
  const t = useT();
  return (
    <IdScope
      value={value}
      onChange={onChange}
      items={locations}
      label={t("pkgFieldFacilityLocationIds")}
      allLabel={t("pkgLocationsAll")}
      someLabel={t("pkgLocationsSome")}
      emptyText={t("pkgNoLocationsYet")}
    />
  );
}

/** "All" or a non-empty selection of named records (class types, locations). */
function IdScope({
  value,
  onChange,
  items,
  label,
  allLabel,
  someLabel,
  emptyText,
}: {
  value: unknown;
  onChange: (value: "all" | string[]) => void;
  items: Array<{ id: string; name: string; archived_at: string | null }>;
  label: string;
  allLabel: string;
  someLabel: string;
  emptyText: string;
}) {
  const active = items.filter((item) => !item.archived_at);
  const selected = Array.isArray(value) ? value.map(String) : [];
  const all = !Array.isArray(value);

  // An empty selection is not a valid scope, so selection needs at least one item.
  if (active.length === 0 && all) {
    return <p className="text-sm" style={{ color: "var(--dim)" }}>{emptyText}</p>;
  }

  return (
    <div className="space-y-3">
      <Segmented
        label={label}
        value={all ? "all" : "some"}
        options={[
          { value: "all", label: allLabel },
          { value: "some", label: someLabel },
        ]}
        onChange={(mode) => onChange(mode === "all" || active.length === 0 ? "all" : [active[0].id])}
      />
      {all ? null : (
        <ChipList
          options={active.map((item) => ({ value: item.id, label: item.name }))}
          value={selected}
          onChange={(next) => onChange(next.length === 0 ? "all" : next)}
        />
      )}
    </div>
  );
}

/** Multi-select chips. */
export function ChipList({
  options,
  value,
  onChange,
}: {
  options: Array<{ value: string; label: string }>;
  value: string[];
  onChange: (value: string[]) => void;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {options.map((option) => {
        const on = value.includes(option.value);
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={on}
            onClick={() => onChange(on ? value.filter((item) => item !== option.value) : [...value, option.value])}
            className="min-h-[2.5rem] rounded-full px-4 text-sm font-semibold"
            style={{
              background: on ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "var(--bg-soft)",
              border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
              color: on ? "var(--primary)" : "var(--text-soft)",
            }}
          >
            {on ? "✓ " : ""}{option.label}
          </button>
        );
      })}
    </div>
  );
}

export function ClassTypeLimits({
  value,
  onChange,
  classTypes,
  scope,
}: {
  value: ClassTypeLimit[];
  onChange: (value: ClassTypeLimit[]) => void;
  classTypes: ClassTypeRecord[];
  scope: unknown;
}) {
  const t = useT();
  const eligible = classTypes.filter(
    (type) => !type.archived_at && (!Array.isArray(scope) || scope.includes(type.id)),
  );
  const unused = eligible.filter((type) => !value.some((limit) => limit.id === type.id));

  return (
    <div className="space-y-2">
      {value.map((limit, index) => (
        <div key={limit.id} className="flex flex-wrap items-center gap-2 rounded-xl p-2" style={{ background: "var(--bg-soft)" }}>
          <select
            aria-label={t("pkgClassType")}
            className={inputClass + " h-11 min-w-[9rem] flex-1"}
            style={inputStyle}
            value={limit.id}
            onChange={(event) => onChange(value.map((item, i) => (i === index ? { ...item, id: event.target.value } : item)))}
          >
            {eligible
              .filter((type) => type.id === limit.id || !value.some((item) => item.id === type.id))
              .map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}
          </select>
          <Stepper label={t("pkgVisits")} value={limit.limit} min={1} onChange={(next) => onChange(value.map((item, i) => (i === index ? { ...item, limit: next } : item)))} />
          <div className="min-w-[9rem]">
            <PeriodSelect
              label={t("pkgResetsEvery")}
              value={limit.period}
              periods={["calendar_week", "calendar_month"]}
              onChange={(period) => onChange(value.map((item, i) => (i === index ? { ...item, period } : item)))}
            />
          </div>
          <button
            type="button"
            className="rounded-full px-3 py-2 text-xs font-semibold"
            style={{ color: "var(--danger)" }}
            onClick={() => onChange(value.filter((_, i) => i !== index))}
          >
            {t("pkgRemove")}
          </button>
        </div>
      ))}
      {unused.length > 0 ? (
        <button
          type="button"
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          onClick={() => onChange([...value, { id: unused[0].id, limit: 4, period: "calendar_month" }])}
        >
          + {t("pkgAddClassTypeLimit")}
        </button>
      ) : null}
    </div>
  );
}

export function DurationControl({
  value,
  onChange,
  label,
  presets,
}: {
  value: DurationValue | null;
  onChange: (value: DurationValue) => void;
  label: string;
  presets: DurationValue[];
}) {
  const t = useT();
  const current = value ?? presets[0];
  const matching = presets.find((preset) => preset.amount === current.amount && preset.unit === current.unit);
  const [custom, setCustom] = useState(!matching);

  return (
    <div className="space-y-2">
      <select
        aria-label={label}
        className={inputClass + " h-11"}
        style={inputStyle}
        value={custom ? "custom" : `${current.amount}:${current.unit}`}
        onChange={(event) => {
          if (event.target.value === "custom") {
            setCustom(true);
            return;
          }
          setCustom(false);
          const [amount, unit] = event.target.value.split(":");
          onChange({ amount: Number(amount), unit: unit as DurationValue["unit"] });
        }}
      >
        {presets.map((preset) => (
          <option key={`${preset.amount}:${preset.unit}`} value={`${preset.amount}:${preset.unit}`}>
            {t(`pkgDuration_${preset.unit}`, { count: preset.amount })}
          </option>
        ))}
        <option value="custom">{t("pkgDurationCustom")}</option>
      </select>
      {custom ? (
        <div className="flex flex-wrap items-center gap-2">
          <Stepper label={label} value={current.amount} min={1} max={current.unit === "day" ? 1095 : current.unit === "week" ? 156 : 36} onChange={(amount) => onChange({ ...current, amount })} />
          <select
            aria-label={t("pkgDurationUnit")}
            className={inputClass + " h-11 max-w-[10rem]"}
            style={inputStyle}
            value={current.unit}
            onChange={(event) => onChange({ ...current, unit: event.target.value as DurationValue["unit"] })}
          >
            {(["day", "week", "month"] as const).map((unit) => <option key={unit} value={unit}>{t(`pkgUnit_${unit}`)}</option>)}
          </select>
        </div>
      ) : null}
    </div>
  );
}

export const VALIDITY_PRESETS: Record<string, DurationValue[]> = {
  class_pack: [1, 2, 3, 6, 12].map((amount) => ({ amount, unit: "month" as const })),
  drop_in: [
    { amount: 1, unit: "day" },
    { amount: 7, unit: "day" },
    { amount: 30, unit: "day" },
    { amount: 90, unit: "day" },
  ],
  trial: [3, 7, 14, 30].map((amount) => ({ amount, unit: "day" as const })),
};

export function AmenitiesControl({ value, onChange, options }: { value: string[]; onChange: (value: string[]) => void; options: string[] }) {
  const t = useT();
  return <ChipList options={options.map((option) => ({ value: option, label: t(`pkgAmenity_${option}`) }))} value={value} onChange={onChange} />;
}

/** Human text for a locked value, used in lock strips and read-only fields. */
export function lockedText(t: UiTranslator, field: string, value: unknown, part?: string): string {
  if (part === "limit") return t("pkgLockedLimit", { count: Number(value) });
  if (part === "period") return t("pkgPeriodWhole");
  if (typeof value === "boolean") return `${t(fieldLabelKey(field))}: ${value ? t("pkgYes") : t("pkgNo")}`;
  if (value === null) return `${t(fieldLabelKey(field))}: ${t("pkgFollowsType")}`;
  if (value === "all") return `${t(fieldLabelKey(field))}: ${t("pkgClassTypesAll")}`;
  if (Array.isArray(value)) return `${t(fieldLabelKey(field))}: ${value.length === 0 ? t("pkgNone") : value.join(", ")}`;
  if (field === "perks.guest_passes" || field === "perks.freeze_days_per_year") return `${t(fieldLabelKey(field))}: 0`;
  return `${t(fieldLabelKey(field))}: ${String(value)}`;
}

/** Preset, follow-up membership and compatible base names needed by MemberPreview for a draft. */
export function previewContext(catalog: PackageCatalog, draft: PackageDraft, packages: FinanceRecord[]) {
  const type = catalog.types.find((candidate) => candidate.key === draft.packageType);
  const conversionId = draft.fields["terms.conversion_package_id"];
  const conversion = typeof conversionId === "string" ? packages.find((pkg) => String(pkg.id) === conversionId) : undefined;
  return {
    preset: type ? presetFor(type, draft.billingPeriod) : undefined,
    conversionName: conversion ? String(conversion.name) : undefined,
    compatibleNames: packageNames(packages, draft.fields["terms.compatible_package_ids"]),
    showAssessments: moduleEnabled(catalog, "personal_training") || draft.fields["personal_training.included"] === true,
  };
}

/** Names of the packages a scope lists, in the scope's order; unknown ids are skipped. */
export function packageNames(packages: FinanceRecord[], ids: unknown): string[] | undefined {
  if (!Array.isArray(ids)) return undefined;
  return ids
    .map((id) => packages.find((pkg) => String(pkg.id) === String(id)))
    .filter((pkg): pkg is FinanceRecord => Boolean(pkg))
    .map((pkg) => String(pkg.name));
}

/** Packages an add-on can be sold with: active membership-type bases (ADR-098). */
function basePackages(packages: FinanceRecord[]) {
  return packages
    .filter((pkg) => pkg.active !== false && pkg.package_type === "membership")
    .map((pkg) => ({ id: String(pkg.id), name: String(pkg.name), archived_at: null }));
}

/** "Any membership" or a selection of membership packages an add-on may join. */
export function CompatiblePackagesScope({ value, onChange, packages }: { value: unknown; onChange: (value: "all" | string[]) => void; packages: FinanceRecord[] }) {
  const t = useT();
  return (
    <IdScope
      value={value}
      onChange={onChange}
      items={basePackages(packages)}
      label={t("pkgFieldTermsCompatiblePackageIds")}
      allLabel={t("pkgCompatibleAll")}
      someLabel={t("pkgCompatibleSome")}
      emptyText={t("pkgNoMembershipsYet")}
    />
  );
}

/** A staff member as the package's trainer; empty means any coach. */
export function CoachSelect({ id, value, onChange, label }: { id?: string; value: unknown; onChange: (value: string | null) => void; label: string }) {
  const t = useT();
  const coaches = useStaffCoaches();
  const current = typeof value === "string" ? value : "";
  const options: CoachOption[] = current && !coaches.some((coach) => coach.id === current) ? [...coaches, { id: current, name: t("pkgCoachCurrent") }] : coaches;
  return (
    <select
      id={id}
      aria-label={id ? undefined : label}
      className={inputClass + " h-11"}
      style={inputStyle}
      value={current}
      onChange={(event) => onChange(event.target.value === "" ? null : event.target.value)}
    >
      <option value="">{t("pkgCoachAny")}</option>
      {options.map((coach) => <option key={coach.id} value={coach.id}>{coach.name || t("pkgCoachUnnamed")}</option>)}
    </select>
  );
}

/** Fixed numeric choices (session length, reply time); `nullable` adds a "none" choice. */
function OptionControl({ spec, value, label, nullable, onChange }: { spec: CatalogField; value: unknown; label: string; nullable: boolean; onChange: (value: number | null) => void }) {
  const t = useT();
  const unit = spec.key === "online_coaching.response_sla_hours" ? "pkgHours" : "pkgMinutes";
  return (
    <Segmented
      label={label}
      value={typeof value === "number" ? String(value) : "none"}
      options={[
        ...(nullable ? [{ value: "none", label: t("pkgNone") }] : []),
        ...(spec.options ?? []).map((option) => ({ value: String(option), label: t(unit, { count: Number(option) }) })),
      ]}
      onChange={(next) => onChange(next === "none" ? null : Number(next))}
    />
  );
}

/** Quiet footnote listing what the type defines; kept out of the main form on purpose. */
export function LockStrip({ type }: { type: CatalogType }) {
  const t = useT();
  const items = type.locks
    .filter((lock) => !lock.field.startsWith("perks.") && !lock.field.startsWith("facility.") && !lock.field.startsWith("personal_training."))
    .map((lock) => {
      const part = lock.path === lock.field ? undefined : lock.path.slice(lock.field.length + 1);
      return lockedText(t, lock.field, lock.value, part);
    });
  if (type.billing_model === "one_off") items.unshift(t("pkgOneOffPayment"));
  if (items.length === 0) return null;
  return (
    <details className="pt-2 text-xs" style={{ color: "var(--dim)", opacity: 0.75 }}>
      <summary className="cursor-pointer select-none list-none">
        ⓘ {t("pkgDefinedByType", { type: t(typeLabelKey(type.key)) })}
      </summary>
      <ul className="mt-1 list-disc space-y-0.5 ps-5">
        {items.map((item, index) => <li key={index}>{item}</li>)}
      </ul>
    </details>
  );
}

/** Number with the field's range; joining fees are edited in currency units. */
function IntegerControl({ spec, value, label, onChange }: { spec: CatalogField; value: unknown; label: string; onChange: (value: number) => void }) {
  const t = useT();
  const locale = useUiLocale();
  const current = typeof value === "number" ? value : 0;
  if (spec.key === "terms.joining_fee_cents") {
    return (
      <div className="flex items-center gap-2">
        <input
          aria-label={label}
          inputMode="decimal"
          className={inputClass + " h-11 max-w-[9rem]"}
          style={inputStyle}
          defaultValue={current === 0 ? "" : String(current / 100)}
          onBlur={(event) => {
            const amount = Number(event.target.value.replace(",", "."));
            onChange(Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) : 0);
          }}
        />
        <span className="text-sm" style={{ color: "var(--dim)" }}>{current > 0 ? money(locale, current) : t("pkgNone")}</span>
      </div>
    );
  }
  return <Stepper label={label} value={current} min={spec.min ?? 0} max={spec.max ?? 10000} onChange={onChange} suffix={t(`${fieldLabelKey(spec.key)}Suffix`, { count: current })} />;
}

const GYM_DEFAULT_STARTS: Record<string, number> = { "booking.window_days": 7, "booking.cancellation_cutoff_hours": 12 };

/** null follows the gym's scheduling default; a number overrides it for this package. */
function GymDefaultControl({ spec, value, label, onChange }: { spec: CatalogField; value: unknown; label: string; onChange: (value: number | null) => void }) {
  const t = useT();
  const custom = typeof value === "number";
  return (
    <div className="space-y-3">
      <Segmented
        label={label}
        value={custom ? "custom" : "default"}
        options={[
          { value: "default", label: t("pkgGymDefault") },
          { value: "custom", label: t("pkgCustomValue") },
        ]}
        onChange={(mode) => onChange(mode === "default" ? null : GYM_DEFAULT_STARTS[spec.key] ?? 1)}
      />
      {custom ? (
        <Stepper
          label={label}
          value={value}
          min={spec.min ?? 0}
          max={spec.max ?? 365}
          onChange={onChange}
          suffix={t(`${fieldLabelKey(spec.key)}Suffix`, { count: value })}
        />
      ) : null}
    </div>
  );
}

export type TimeWindow = { days: number[]; from: string; to: string };

const ISO_WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];

/** Short weekday names in the UI locale; ISO weekdays start on Monday. */
function weekdayNames(locale: string) {
  const format = new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" });
  // 2024-01-01 was a Monday.
  return ISO_WEEKDAYS.map((day) => format.format(new Date(Date.UTC(2024, 0, day))));
}

/** Allowed booking hours: an empty list means any time. */
function TimeWindowsControl({ value, onChange }: { value: TimeWindow[]; onChange: (value: TimeWindow[]) => void }) {
  const t = useT();
  const locale = useUiLocale();
  const names = weekdayNames(locale);
  const update = (index: number, patch: Partial<TimeWindow>) => onChange(value.map((window, i) => (i === index ? { ...window, ...patch } : window)));

  return (
    <div className="space-y-3">
      {value.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("pkgTimeWindowsAnyTime")}</p> : null}
      {value.map((window, index) => (
        <div key={index} className="space-y-2 rounded-xl p-3" style={{ background: "var(--bg-soft)" }}>
          <ChipList
            options={ISO_WEEKDAYS.map((day) => ({ value: String(day), label: names[day - 1] }))}
            value={window.days.map(String)}
            onChange={(days) => update(index, { days: days.map(Number).sort((a, b) => a - b) })}
          />
          <div className="flex flex-wrap items-center gap-2">
            <input type="time" aria-label={t("pkgTimeWindowFrom")} className={inputClass + " h-11 max-w-[8rem]"} style={inputStyle} value={window.from} onChange={(event) => update(index, { from: event.target.value })} />
            <span className="text-sm" style={{ color: "var(--dim)" }}>{t("pkgTimeWindowTo")}</span>
            <input type="time" aria-label={t("pkgTimeWindowTo")} className={inputClass + " h-11 max-w-[8rem]"} style={inputStyle} value={window.to} onChange={(event) => update(index, { to: event.target.value })} />
            <button type="button" className="ms-auto text-sm font-semibold" style={{ color: "var(--danger)" }} onClick={() => onChange(value.filter((_, i) => i !== index))}>
              {t("pkgRemove")}
            </button>
          </div>
          {window.days.length === 0 || window.from >= window.to ? <p className="text-xs" style={{ color: "var(--danger)" }}>{t("pkgTimeWindowInvalid")}</p> : null}
        </div>
      ))}
      <button
        type="button"
        className="min-h-[2.5rem] rounded-full px-4 text-sm font-semibold"
        style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text)" }}
        onClick={() => onChange([...value, { days: [1, 2, 3, 4, 5], from: "06:00", to: "16:00" }])}
      >
        {t("pkgTimeWindowAdd")}
      </button>
    </div>
  );
}

const QUOTA_UNITS: Record<string, string> = {
  "group_classes.visits": "pkgVisits",
  "facility.open_gym_visits": "pkgUnitOpenGymVisits",
  "perks.guest_passes": "pkgUnitGuestPasses",
  "perks.event_visits": "pkgUnitEvents",
  "personal_training.sessions": "pkgUnitSessions",
  "online_coaching.form_reviews": "pkgUnitFormReviews",
};

/** Generic control for any available catalog field (used by advanced settings and the editor). */
export function FieldControl({
  spec,
  type,
  draft,
  onFieldChange,
  context,
  preset,
}: {
  spec: CatalogField;
  type: CatalogType;
  draft: PackageDraft;
  onFieldChange: (key: string, value: unknown) => void;
  context: FieldContext;
  preset: Record<string, unknown>;
}) {
  const t = useT();
  const id = useId();
  const value = draft.fields[spec.key];
  const label = t(fieldLabelKey(spec.key));
  const changed = !equal(value, preset[spec.key]);
  const hint = t(`${fieldLabelKey(spec.key)}Hint`);

  if (isFieldLocked(type, spec.key)) {
    const lock = fieldLocks(type, spec.key)[0];
    return (
      <FieldShell label={label}>
        <LockedValue text={lockedText(t, spec.key, lock.value)} reason={t(lockReasonKey(lock.reason))} />
      </FieldShell>
    );
  }

  const reset = () => onFieldChange(spec.key, preset[spec.key]);
  let control: ReactNode;

  switch (spec.kind) {
    case "boolean":
      control = (
        <div className="flex items-center justify-between gap-3 rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}>
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>{value === true ? t("pkgYes") : t("pkgNo")}</span>
          <Toggle label={label} checked={value === true} onChange={(next) => onFieldChange(spec.key, next)} />
        </div>
      );
      break;
    case "quota":
      control = (
        <QuotaControl
          type={type}
          fieldKey={spec.key}
          value={value as QuotaValue}
          onChange={(next) => onFieldChange(spec.key, next)}
          label={label}
          unitLabel={t(QUOTA_UNITS[spec.key] ?? "pkgCheckIns")}
        />
      );
      break;
    case "duration":
      control = (
        <DurationControl
          label={label}
          value={(value as DurationValue | null) ?? null}
          presets={VALIDITY_PRESETS[type.key] ?? VALIDITY_PRESETS.class_pack}
          onChange={(next) => onFieldChange(spec.key, next)}
        />
      );
      break;
    case "scope_ids":
      control =
        spec.key === "facility.location_ids" ? (
          <LocationScope value={value} locations={context.locations} onChange={(next) => onFieldChange(spec.key, next)} />
        ) : spec.key === "terms.compatible_package_ids" ? (
          <CompatiblePackagesScope value={value} packages={context.packages} onChange={(next) => onFieldChange(spec.key, next)} />
        ) : (
          <ClassTypeScope value={value} classTypes={context.classTypes} onChange={(next) => onFieldChange(spec.key, next)} />
        );
      break;
    case "integer":
      control = (
        <IntegerControl
          // Semi-private sessions are for 2–4 people (backend rule).
          spec={spec.key === "personal_training.group_size" && draft.fields["personal_training.format"] === "semi_private" ? { ...spec, min: 2 } : spec}
          value={value}
          label={label}
          onChange={(next) => onFieldChange(spec.key, next)}
        />
      );
      break;
    case "integer_option":
    case "integer_option_or_null":
      control = <OptionControl spec={spec} value={value} label={label} nullable={spec.kind === "integer_option_or_null"} onChange={(next) => onFieldChange(spec.key, next)} />;
      break;
    case "gym_default_integer":
      control = <GymDefaultControl spec={spec} value={value} label={label} onChange={(next) => onFieldChange(spec.key, next)} />;
      break;
    case "enum":
      control = (
        <Segmented
          label={label}
          value={String(value)}
          options={(spec.options ?? []).map((option) => ({ value: String(option), label: t(`${fieldLabelKey(spec.key)}_${option}`) }))}
          onChange={(next) => onFieldChange(spec.key, next)}
        />
      );
      break;
    case "time_windows":
      control = <TimeWindowsControl value={(value as TimeWindow[]) ?? []} onChange={(next) => onFieldChange(spec.key, next)} />;
      break;
    case "quota_by_id":
      control = (
        <ClassTypeLimits
          value={(value as ClassTypeLimit[]) ?? []}
          classTypes={context.classTypes}
          scope={draft.fields["group_classes.class_types"]}
          onChange={(next) => onFieldChange(spec.key, next)}
        />
      );
      break;
    case "enum_list":
      control =
        spec.key === "facility.amenities" ? (
          <AmenitiesControl value={(value as string[]) ?? []} options={(spec.options ?? []).map(String)} onChange={(next) => onFieldChange(spec.key, next)} />
        ) : (
          <ChipList
            options={(spec.options ?? []).map((option) => ({ value: String(option), label: t(`${fieldLabelKey(spec.key)}_${option}`) }))}
            value={(value as string[]) ?? []}
            onChange={(next) => onFieldChange(spec.key, next)}
          />
        );
      break;
    case "string_or_null":
      control =
        spec.key === "terms.enrollment_domain" ? (
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold" style={{ color: "var(--dim)" }} aria-hidden="true">@</span>
            <input
              id={id}
              className={inputClass + " h-11"}
              style={inputStyle}
              maxLength={spec.max}
              inputMode="url"
              autoCapitalize="none"
              spellCheck={false}
              placeholder={t("pkgFieldTermsEnrollmentDomainPlaceholder")}
              value={typeof value === "string" ? value : ""}
              onChange={(event) => {
                const domain = event.target.value.trim().replace(/^@+/, "").toLowerCase();
                onFieldChange(spec.key, domain === "" ? null : domain);
              }}
            />
          </div>
        ) : (
          <input
            id={id}
            className={inputClass}
            style={inputStyle}
            maxLength={spec.max}
            value={typeof value === "string" ? value : ""}
            onChange={(event) => onFieldChange(spec.key, event.target.value === "" ? null : event.target.value)}
          />
        );
      break;
    case "uuid_or_null":
      control = spec.key === "personal_training.coach_id" ? (
        <CoachSelect id={id} label={label} value={value} onChange={(next) => onFieldChange(spec.key, next)} />
      ) : (
        <select
          id={id}
          className={inputClass + " h-11"}
          style={inputStyle}
          value={typeof value === "string" ? value : ""}
          onChange={(event) => onFieldChange(spec.key, event.target.value === "" ? null : event.target.value)}
        >
          <option value="">{t("pkgNone")}</option>
          {context.packages
            .filter((pkg) => pkg.active !== false && pkg.package_type === "membership")
            .map((pkg) => <option key={String(pkg.id)} value={String(pkg.id)}>{String(pkg.name)}</option>)}
        </select>
      );
      break;
    default:
      control = (
        <input
          id={id}
          inputMode="numeric"
          className={inputClass}
          style={inputStyle}
          value={value == null ? "" : String(value)}
          onChange={(event) => onFieldChange(spec.key, event.target.value === "" ? null : Number(event.target.value))}
        />
      );
  }

  return (
    <FieldShell label={label} hint={hint} changed={changed} onReset={reset} htmlFor={id}>
      {control}
    </FieldShell>
  );
}

/**
 * Phase B fields that depend on a module or another field stay out of the way
 * until they mean something (ADR-097): open gym and events need their module,
 * their quotas need the service switched on, and location scopes need locations.
 */
function phaseBFieldVisible(key: string, draft: PackageDraft, catalog: PackageCatalog, context: FieldContext) {
  const on = (field: string) => draft.fields[field] === true;
  const enabled = (module: string) => catalog.modules.some((candidate) => candidate.key === module && candidate.enabled);
  switch (key) {
    case "facility.open_gym":
      return enabled("open_gym") || on(key);
    case "facility.open_gym_visits":
      return on("facility.open_gym");
    case "perks.events":
      return enabled("events") || on(key);
    case "perks.event_visits":
      return on("perks.events");
    case "facility.location_ids":
      return context.locations.some((location) => !location.archived_at) || Array.isArray(draft.fields[key]);
    case "perks.member_discount_scope":
      return typeof draft.fields["perks.member_discount_percent"] === "number" && (draft.fields["perks.member_discount_percent"] as number) > 0;
    default:
      return true;
  }
}

/**
 * Phase C fields follow the same idea (ADR-098): trainer details need personal
 * training switched on, coaching extras need coaching, and payment-model terms
 * appear only for the type that uses them.
 */
export function phaseCFieldVisible(key: string, draft: PackageDraft) {
  const on = (field: string) => draft.fields[field] === true;
  const type = draft.packageType;
  switch (key) {
    case "personal_training.sessions":
    case "personal_training.format":
    case "personal_training.session_minutes":
    case "personal_training.coach_id":
      return on("personal_training.included");
    case "personal_training.group_size":
      return on("personal_training.included") && draft.fields["personal_training.format"] === "semi_private";
    case "online_coaching.form_reviews":
      return on("online_coaching.included");
    case "online_coaching.response_sla_hours":
      return on("online_coaching.included") && on("online_coaching.messaging");
    case "terms.compatible_package_ids":
      return type === "add_on";
    case "terms.beneficiaries":
    case "terms.quota_sharing":
    case "terms.allow_minor_beneficiaries":
      return type === "shared";
    case "terms.seats":
    case "terms.seat_billing":
    case "terms.enrollment":
      return type === "corporate";
    case "terms.enrollment_domain":
      return type === "corporate" && draft.fields["terms.enrollment"] === "email_domain";
    default:
      return true;
  }
}

/** A section shows when its module is on, or when the draft already uses it (so nothing is hidden silently). */
export function sectionVisible(section: string, draft: PackageDraft, catalog: PackageCatalog) {
  const on = (field: string) => draft.fields[field] === true;
  switch (section) {
    case "group_classes":
      return moduleEnabled(catalog, "group_classes") || on("group_classes.included");
    case "online_coaching":
      return moduleEnabled(catalog, "online_coaching") || on("online_coaching.included") || on("online_coaching.nutrition_plan");
    case "personal_training":
      // Assessments alone (the trial preset has one) do not open the section without the module.
      return moduleEnabled(catalog, "personal_training") || on("personal_training.included");
    case "content":
      return moduleEnabled(catalog, "digital_content") || on("content.on_demand_video") || on("content.advanced_analytics");
    default:
      return true;
  }
}

const ADVANCED_SECTIONS = ["terms", "group_classes", "booking", "personal_training", "online_coaching", "content", "facility", "perks"];

/** Field changes that keep dependent values valid (switching PT format resets the group size). */
export function withDependents(key: string, value: unknown, draft: PackageDraft): Array<[string, unknown]> {
  const changes: Array<[string, unknown]> = [[key, value]];
  if (key === "personal_training.format") {
    changes.push(["personal_training.group_size", groupSizeForFormat(value, draft.fields["personal_training.group_size"])]);
  }
  return changes;
}

/** Every available catalog field, grouped by section, with search and reset. */
export function AdvancedSettings({
  catalog,
  type,
  draft,
  onFieldChange,
  onResetAll,
  context,
  changedCount,
}: {
  catalog: PackageCatalog;
  type: CatalogType;
  draft: PackageDraft;
  onFieldChange: (key: string, value: unknown) => void;
  onResetAll: () => void;
  context: FieldContext;
  changedCount: number;
}) {
  const t = useT();
  const [query, setQuery] = useState("");
  const preset = useMemo(() => presetFor(type, draft.billingPeriod), [type, draft.billingPeriod]);
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const changeField = (key: string, value: unknown) => {
    for (const [field, next] of withDependents(key, value, draft)) onFieldChange(field, next);
  };

  const sections = ADVANCED_SECTIONS.filter((section) => sectionVisible(section, draft, catalog))
    .map((section) => ({
      section,
      fields: catalog.fields.filter(
        (field) =>
          field.available &&
          // Retired fields (content.workout_library) stay readable for stored contracts but are never authored.
          field.phase !== "retired" &&
          field.section === section &&
          (normalizedQuery === "" || t(fieldLabelKey(field.key)).toLocaleLowerCase().includes(normalizedQuery)) &&
          (field.key !== "terms.conversion_package_id" || type.key === "trial") &&
          (field.key !== "terms.validity" || type.billing_model === "one_off" || isFieldLocked(type, field.key)) &&
          phaseBFieldVisible(field.key, draft, catalog, context) &&
          phaseCFieldVisible(field.key, draft),
      ),
    }))
    .filter((group) => group.fields.length > 0);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="search"
          aria-label={t("pkgSearchSettings")}
          placeholder={t("pkgSearchSettings")}
          className={inputClass + " h-11 min-w-[12rem] flex-1"}
          style={inputStyle}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <button
          type="button"
          disabled={changedCount === 0}
          onClick={onResetAll}
          className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-40"
          style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          ↺ {t("pkgResetAll")}
        </button>
      </div>
      {sections.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("pkgNoMatchingSettings")}</p> : null}
      {sections.map(({ section, fields }) => (
        <details key={section} open={normalizedQuery !== "" || section === "group_classes"} className="rounded-2xl" style={{ border: "1px solid var(--border)", background: "var(--panel)" }}>
          <summary className="cursor-pointer px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t(sectionLabelKey(section))}
          </summary>
          <div className="space-y-5 px-4 pb-4">
            {fields.map((spec) => (
              <FieldControl key={spec.key} spec={spec} type={type} draft={draft} onFieldChange={changeField} context={context} preset={preset} />
            ))}
          </div>
        </details>
      ))}
    </div>
  );
}

export function MemberPreview({
  draft,
  classTypes,
  compact,
  preset,
  conversionName,
  compatibleNames,
  showAssessments,
}: {
  draft: PackageDraft;
  classTypes: ClassTypeRecord[];
  compact?: boolean;
  /** Type preset; advanced values that differ from it are described like any other benefit. */
  preset?: Record<string, unknown>;
  conversionName?: string;
  compatibleNames?: string[];
  /** False hides preset assessments while personal training is not offered. */
  showAssessments?: boolean;
}) {
  const t = useT();
  const locale = useUiLocale();
  const names = useMemo(() => new Map(classTypes.map((type) => [type.id, type.name])), [classTypes]);
  const coachId = draft.fields["personal_training.coach_id"];
  const coaches = useStaffCoaches(typeof coachId === "string");
  const summaryNames: SummaryNames = {
    coachName: coaches.find((coach) => coach.id === coachId)?.name ?? undefined,
    compatibleNames,
    showAssessments,
  };
  const lines = memberSummary(draft, names, preset ?? null, conversionName, summaryNames);
  const cents = priceCents(draft.price);
  const suffix = priceSuffix(t, draft.billingPeriod);

  return (
    <section
      aria-live="polite"
      aria-label={t("pkgMemberPreview")}
      className={"rounded-2xl " + (compact ? "p-4" : "p-5")}
      style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}
    >
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("pkgMemberPreview")}</p>
      <p className={"mt-2 font-semibold " + (compact ? "text-base" : "text-lg")} style={{ color: "var(--text)" }}>
        {draft.name.trim() || t("pkgUntitled")}
      </p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t(typeLabelKey(draft.packageType))}
        {cents !== null ? ` · ${money(locale, cents)} ${suffix}` : ""}
      </p>
      {draft.description.trim() ? <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{draft.description.trim()}</p> : null}
      <ul className="mt-3 space-y-1 text-sm" style={{ color: "var(--text)" }}>
        {lines.map((line, index) => (
          <li key={index} className="flex gap-2">
            <span aria-hidden="true" style={{ color: "var(--success)" }}>✓</span>
            <span>
              {line.key === "pkgSummaryAmenities"
                ? t(line.key, { list: String(line.params?.list ?? "").split("|").map((item) => t(`pkgAmenity_${item}`)).join(", ") })
                : typeof line.params?.cents === "number"
                  ? t(line.key, { amount: money(locale, line.params.cents) })
                  : t(line.key, line.params)}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** "/ month", "in total" or "with your membership", following how the package is billed. */
export function priceSuffix(t: UiTranslator, billingPeriod: string) {
  return billingPeriod === "one_off" ? t("pkgPriceSuffixTotal") : t(`pkgPriceSuffix_${billingPeriod}`);
}

/** Readable text for a stored field value (package detail and summaries for staff). */
export function fieldValueText(t: UiTranslator, spec: CatalogField, value: unknown, names: { coaches: CoachOption[]; packages: FinanceRecord[] }): string {
  if (value === null || value === undefined) return spec.key === "personal_training.coach_id" ? t("pkgCoachAny") : t("pkgNone");
  if (typeof value === "boolean") return value ? t("pkgYes") : t("pkgNo");
  if (spec.key === "personal_training.coach_id") {
    const coach = names.coaches.find((candidate) => candidate.id === value);
    return coach ? coach.name || t("pkgCoachUnnamed") : t("pkgCoachCurrent");
  }
  if (spec.key === "terms.compatible_package_ids") return value === "all" ? t("pkgCompatibleAll") : (packageNames(names.packages, value) ?? []).join(", ");
  if (spec.kind === "enum") return t(`${fieldLabelKey(spec.key)}_${String(value)}`);
  if (spec.key === "personal_training.session_minutes") return t("pkgMinutes", { count: Number(value) });
  if (spec.key === "online_coaching.response_sla_hours") return t("pkgHours", { count: Number(value) });
  if (spec.key === "terms.enrollment_domain") return `@${String(value)}`;
  if (spec.kind === "quota") {
    const quota = value as QuotaValue;
    if (quota.limit === "unlimited") return t("pkgUnlimited");
    if (quota.limit === 0) return t("pkgNone");
    return `${quota.limit} ${t(QUOTA_UNITS[spec.key] ?? "pkgCheckIns")} ${t(`pkgPeriod_${quota.period}`)}`;
  }
  if (spec.kind === "integer") return `${String(value)} ${t(`${fieldLabelKey(spec.key)}Suffix`, { count: Number(value) })}`;
  return String(value);
}

/** Staff-facing Phase C terms that members do not see in the preview (ADR-098). */
const CONTRACT_DETAIL_FIELDS = [
  "personal_training.format",
  "personal_training.group_size",
  "personal_training.session_minutes",
  "personal_training.coach_id",
  "online_coaching.response_sla_hours",
  "terms.compatible_package_ids",
  "terms.beneficiaries",
  "terms.quota_sharing",
  "terms.allow_minor_beneficiaries",
  "terms.seats",
  "terms.seat_billing",
  "terms.enrollment",
  "terms.enrollment_domain",
];

/** Personal training, add-on, shared and corporate terms of a stored package, as label/value rows. */
export function PackageContractDetails({ catalog, draft, packages }: { catalog: PackageCatalog; draft: PackageDraft; packages: FinanceRecord[] }) {
  const t = useT();
  const coachId = draft.fields["personal_training.coach_id"];
  const coaches = useStaffCoaches(typeof coachId === "string");
  const rows = CONTRACT_DETAIL_FIELDS.map((key) => fieldSpec(catalog, key))
    .filter((spec): spec is CatalogField => Boolean(spec?.available) && phaseCFieldVisible(spec!.key, draft))
    .filter((spec) => spec.section !== "online_coaching" || draft.fields["online_coaching.response_sla_hours"] !== null)
    .map((spec) => ({ key: spec.key, label: t(fieldLabelKey(spec.key)), value: fieldValueText(t, spec, draft.fields[spec.key], { coaches, packages }) }));
  if (rows.length === 0) return null;
  return (
    <dl className="grid gap-4 sm:grid-cols-2">
      {rows.map((row) => (
        <div key={row.key}>
          <dt className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{row.label}</dt>
          <dd className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{row.value || "—"}</dd>
        </div>
      ))}
    </dl>
  );
}
