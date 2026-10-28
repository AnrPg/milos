"use client";

import { useTranslations } from "next-intl";

import type { DayWorkout } from "@/api/day-workouts";
import type { ClassTypeRecord } from "@/api/schedule";

const MAX_SHOWN = 2;

/**
 * ADR-224: the day's WOD under a day's header, like a calendar's all-day row.
 * A set day WOD shows its title (and class type when it is not for every
 * class); a day without one offers a quiet «+ WOD ημέρας» to staff, only on
 * days that have classes. In the month grid it is one small line that opens
 * the day.
 */
export function DayWorkoutStrip({
  date,
  rules,
  classTypes = [],
  variant,
  canAdd = false,
  onOpen,
}: {
  date: string;
  /** The day's rules, all-classes first. */
  rules: DayWorkout[];
  classTypes?: ClassTypeRecord[];
  variant: "full" | "compact" | "month";
  canAdd?: boolean;
  onOpen?: () => void;
}) {
  const t = useTranslations("Schedule");
  const typeName = (id: string | null) => (id ? classTypes.find((type) => type.id === id)?.name ?? null : null);
  const label = (rule: DayWorkout) =>
    [rule.workout?.title ?? "WOD", typeName(rule.class_type_id)].filter(Boolean).join(" · ");

  if (!rules.length) {
    if (!canAdd || !onOpen || variant === "month") return null;
    return (
      <button
        type="button"
        className="mt-3 w-full truncate rounded-full px-3 py-1 text-start text-[11px] font-semibold transition-opacity hover:opacity-80"
        style={{ border: "1px dashed var(--border-strong)", color: "var(--muted)" }}
        onClick={onOpen}
        data-testid={`day-wod-add-${date}`}
      >
        {t("dayWodAdd")}
      </button>
    );
  }

  if (variant === "month") {
    const first = rules[0];
    return (
      <button
        type="button"
        className="mt-0.5 w-full truncate rounded px-1 text-start text-[9px] font-bold disabled:cursor-default"
        style={{ color: "var(--primary)" }}
        onClick={onOpen}
        disabled={!onOpen}
        aria-label={t("dayWodAria", { title: label(first) })}
        data-testid={`day-wod-${date}`}
      >
        {t("dayWodAria", { title: label(first) })}
        {rules.length > 1 ? ` +${rules.length - 1}` : ""}
      </button>
    );
  }

  const shown = rules.slice(0, MAX_SHOWN);
  const content = (
    <>
      <span className="text-[10px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--primary)" }}>
        {t("dayWodLabel")}
      </span>
      {shown.map((rule) => (
        <span key={rule.id} className="block truncate text-xs font-semibold" style={{ color: "var(--text)" }}>
          {label(rule)}
        </span>
      ))}
      {rules.length > MAX_SHOWN ? (
        <span className="block text-[10px]" style={{ color: "var(--muted)" }}>
          +{rules.length - MAX_SHOWN}
        </span>
      ) : null}
    </>
  );
  const style = {
    background: "color-mix(in srgb, var(--primary) 9%, transparent)",
    border: "1px solid color-mix(in srgb, var(--primary) 28%, transparent)",
  };
  const padding = variant === "compact" ? "px-2.5 py-1.5" : "px-3 py-2";
  const frame = "mt-3 block w-full rounded-2xl text-start " + padding;

  return onOpen ? (
    <button
      type="button"
      className={frame + " transition-opacity hover:opacity-85"}
      style={style}
      onClick={onOpen}
      aria-label={t("dayWodAria", { title: rules.map(label).join(", ") })}
      data-testid={`day-wod-${date}`}
    >
      {content}
    </button>
  ) : (
    <div className={frame} style={style} data-testid={`day-wod-${date}`}>
      {content}
    </div>
  );
}
