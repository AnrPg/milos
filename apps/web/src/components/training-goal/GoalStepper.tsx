"use client";

import { useTranslations } from "next-intl";

import { stepGoal } from "@/components/training-goal/training-goal";

/** − N + for the weekly workout goal (ADR-216); every press is one change. */
export function GoalStepper({
  value,
  min,
  max,
  disabled,
  onChange,
}: {
  value: number;
  min: number;
  max: number;
  disabled?: boolean;
  onChange: (next: number) => void;
}) {
  const t = useTranslations("TrainingGoal");
  const bounds = { min, max };
  const buttonStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <div className="flex items-center gap-3" role="group" aria-label={t("title")}>
      <button
        type="button"
        className="hit-area h-11 w-11 rounded-full text-lg font-semibold disabled:opacity-40"
        style={buttonStyle}
        aria-label={t("decrease")}
        disabled={disabled || value <= min}
        onClick={() => onChange(stepGoal(value, -1, bounds))}
      >
        −
      </button>
      <output className="min-w-[9rem] text-center text-sm font-semibold" style={{ color: "var(--text)" }} aria-live="polite" data-testid="training-goal-value">
        {t("perWeek", { count: value })}
      </output>
      <button
        type="button"
        className="hit-area h-11 w-11 rounded-full text-lg font-semibold disabled:opacity-40"
        style={buttonStyle}
        aria-label={t("increase")}
        disabled={disabled || value >= max}
        onClick={() => onChange(stepGoal(value, 1, bounds))}
      >
        +
      </button>
    </div>
  );
}
