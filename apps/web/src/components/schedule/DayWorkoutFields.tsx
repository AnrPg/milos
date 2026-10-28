"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { previewDayWorkout, type DayWorkoutClass, type DayWorkoutRequest } from "@/api/day-workouts";
import type { ClassTypeRecord, ScheduleLocation } from "@/api/schedule";
import { Select } from "@/components/ui/Select";
import { formatInZone } from "@/lib/zoned-time";

/**
 * ADR-224: the parts shared by every place a day WOD is set (the schedule's
 * day dialog, the library's «Ανάθεση → Ημέρα»): which classes it is for,
 * and what it will change before it is saved (count, the classes keeping
 * their own WOD with a «give them the day WOD too» choice, the classes that
 * already started).
 */

export type DayWorkoutScopeValue = {
  /** Empty: every class of the day. */
  classTypeIds: string[];
  mode: "all" | "types";
  /** Null: every branch. */
  locationId: string | null;
};

export const ALL_CLASSES: DayWorkoutScopeValue = { mode: "all", classTypeIds: [], locationId: null };

export function scopeIsComplete(scope: DayWorkoutScopeValue) {
  return scope.mode === "all" || scope.classTypeIds.length > 0;
}

export function scopeRequest(scope: DayWorkoutScopeValue): Pick<DayWorkoutRequest, "class_type_ids" | "location_id"> {
  return {
    class_type_ids: scope.mode === "all" ? [] : scope.classTypeIds,
    location_id: scope.locationId,
  };
}

export function DayWorkoutScopeFields({
  value,
  onChange,
  classTypes,
  locations = [],
  disabled = false,
}: {
  value: DayWorkoutScopeValue;
  onChange: (value: DayWorkoutScopeValue) => void;
  classTypes: ClassTypeRecord[];
  /** Offered only when the gym has more than one branch. */
  locations?: ScheduleLocation[];
  disabled?: boolean;
}) {
  const t = useTranslations("Schedule");
  const active = classTypes.filter((type) => !type.archived_at);

  function toggleType(id: string) {
    const classTypeIds = value.classTypeIds.includes(id)
      ? value.classTypeIds.filter((current) => current !== id)
      : [...value.classTypeIds, id];
    onChange({ ...value, classTypeIds });
  }

  return (
    <div className="space-y-3">
      <fieldset disabled={disabled}>
        <legend className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {t("dayWodScopeLabel")}
        </legend>
        <div className="mt-2 flex rounded-full p-1" style={{ background: "var(--border)" }} role="radiogroup">
          {(["all", "types"] as const).map((mode) => (
            <button
              key={mode}
              type="button"
              role="radio"
              aria-checked={value.mode === mode}
              className="flex-1 rounded-full px-3 py-2 text-xs font-bold"
              style={value.mode === mode ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--dim)" }}
              onClick={() => onChange({ ...value, mode })}
            >
              {mode === "all" ? t("dayWodScopeAll") : t("dayWodScopeTypes")}
            </button>
          ))}
        </div>

        {value.mode === "types" ? (
          <div className="mt-3 flex flex-wrap gap-2" data-testid="day-wod-types">
            {active.map((type) => {
              const on = value.classTypeIds.includes(type.id);
              return (
                <button
                  key={type.id}
                  type="button"
                  aria-pressed={on}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold"
                  style={
                    on
                      ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                      : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }
                  }
                  onClick={() => toggleType(type.id)}
                >
                  {type.name}
                </button>
              );
            })}
            {value.classTypeIds.length === 0 ? (
              <p className="w-full text-xs" style={{ color: "var(--muted)" }}>
                {t("dayWodTypesHint")}
              </p>
            ) : null}
          </div>
        ) : null}
      </fieldset>

      {locations.length > 1 ? (
        <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {t("dayWodBranchLabel")}
          <Select
            className="mt-2 w-full rounded-2xl px-4 py-3 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={value.locationId ?? ""}
            disabled={disabled}
            onValueChange={(locationId) => onChange({ ...value, locationId: locationId || null })}
          >
            <option value="">{t("dayWodAllBranches")}</option>
            {locations.map((location) => (
              <option key={location.id} value={location.id}>
                {location.name}
              </option>
            ))}
          </Select>
        </label>
      ) : null}
    </div>
  );
}

function useDebounced<T>(value: T, delay = 250) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

/** «5 μαθήματα θα το πάρουν · 1 κρατά δικό του WOD», before saving. */
export function DayWorkoutPreviewNote({
  token,
  request,
  replaceOwn,
  onReplaceOwnChange,
  timeZone,
}: {
  token: string;
  /** Null until the WOD and scope are chosen. */
  request: DayWorkoutRequest | null;
  replaceOwn: boolean;
  onReplaceOwnChange: (value: boolean) => void;
  timeZone: string | null;
}) {
  const t = useTranslations("Schedule");
  const locale = useLocale();
  const debounced = useDebounced(request);
  const preview = useQuery({
    queryKey: ["day-workout-preview", debounced],
    enabled: Boolean(token && debounced),
    queryFn: () => previewDayWorkout(token, debounced!),
    staleTime: 10_000,
  });

  if (!request || !preview.data) return null;

  const { inherit, own, started } = preview.data;
  const label = (item: DayWorkoutClass) =>
    `${formatInZone(item.scheduled_at, timeZone, locale, "time")} ${item.class_type_name ?? item.name}`;

  return (
    <div
      className="space-y-2 rounded-2xl px-4 py-3 text-sm"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      aria-live="polite"
      data-testid="day-wod-preview"
    >
      <p>{t("dayWodPreviewInherit", { count: inherit.length })}</p>
      {own.length ? (
        <div>
          <p>
            {t("dayWodPreviewOwn", { count: own.length })} {own.map(label).join(", ")}
          </p>
          <label className="mt-2 flex items-center gap-2 text-xs font-semibold" style={{ color: "var(--text)" }}>
            <input type="checkbox" checked={replaceOwn} onChange={(event) => onReplaceOwnChange(event.target.checked)} />
            {t("dayWodReplaceOwn")}
          </label>
        </div>
      ) : null}
      {started.length ? (
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {t("dayWodPreviewStarted", { count: started.length })}
        </p>
      ) : null}
    </div>
  );
}
