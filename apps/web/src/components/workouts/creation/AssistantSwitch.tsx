"use client";

import { useId } from "react";

import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-180: the workout editor's «AI assistant» switch. On, the coach writes
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
  const hintId = useId();
  const hint = !available
    ? i18n("workoutAssistantSwitchGymOff")
    : enabled
      ? i18n("workoutAssistantSwitchOnHint")
      : i18n("workoutAssistantSwitchOffHint");
  // One line beside the editor's tabs; what on and off mean is the tooltip.
  return (
    <label className="flex min-h-9 items-center gap-2 whitespace-nowrap" title={hint} data-testid="assistant-switch">
      <span className="text-xs font-bold" style={{ color: "var(--text)" }}>
        <span aria-hidden="true">✨ </span>
        {i18n("workoutAssistantSwitchLabel")}
      </span>
      <span id={hintId} className="sr-only">
        {hint}
      </span>
      <input
        type="checkbox"
        role="switch"
        aria-label={i18n("workoutAssistantSwitchLabel")}
        aria-describedby={hintId}
        checked={enabled && available}
        disabled={!available}
        onChange={(event) => onChange(event.target.checked)}
        className="h-5 w-5 shrink-0 disabled:opacity-40"
        style={{ accentColor: "var(--primary)" }}
      />
    </label>
  );
}
