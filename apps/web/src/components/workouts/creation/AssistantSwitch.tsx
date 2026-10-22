"use client";

import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-179: the workout editor's «AI assistant» switch. On, the coach writes
 * one free text the assistant reads (guided execution); off, the workout is
 * written in sections with a timer each. When the gym switched the assistant
 * off in Settings, the switch stays off and says so.
 */
export function AssistantSwitch({
  enabled,
  available,
  onChange,
}: {
  enabled: boolean;
  available: boolean;
  onChange: (enabled: boolean) => void;
}) {
  const i18n = useUiTranslations();
  return (
    <label className="flex min-h-11 items-center gap-3" data-testid="assistant-switch">
      <span className="flex flex-col text-end">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
          {i18n("workoutAssistantSwitchLabel")}
        </span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {!available
            ? i18n("workoutAssistantSwitchGymOff")
            : enabled
              ? i18n("workoutAssistantSwitchOnHint")
              : i18n("workoutAssistantSwitchOffHint")}
        </span>
      </span>
      <input
        type="checkbox"
        role="switch"
        aria-label={i18n("workoutAssistantSwitchLabel")}
        checked={enabled && available}
        disabled={!available}
        onChange={(event) => onChange(event.target.checked)}
        className="h-5 w-5 shrink-0 disabled:opacity-40"
        style={{ accentColor: "var(--primary)" }}
      />
    </label>
  );
}
