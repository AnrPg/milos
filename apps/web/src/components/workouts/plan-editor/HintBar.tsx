"use client";

import { useTranslations } from "next-intl";

import type { PlanWizardStep } from "@/stores/structured-plan";

import { keyLabel } from "./keymap";

type HintKey = "section" | "open" | "newSection" | "all" | "search" | "choose" | "continue" | "close" | "nextField" | "nextStep" | "back" | "newExercise" | "actions" | "differentRound" | "score";

/**
 * One quiet line with the few keys that matter where the coach is; «?»
 * lists the rest.
 */
export function HintBar({ open, step, mac, status }: { open: boolean; step: PlanWizardStep; mac: boolean; status: string | null }) {
  const t = useTranslations("PlanEditor");
  const items: [string, HintKey][] = !open
    ? [["↑ ↓", "section"], ["Enter", "open"], ["Shift+Enter", "newSection"], ["?", "all"]]
    : step === 0
      ? [["↑ ↓", "choose"], ["Enter", "continue"], ["Esc", "close"]]
      : step !== 2
        ? [["Tab", "nextField"], ["Enter", "nextStep"], ["Alt+←", "back"], ["Esc", "close"]]
        : [["Enter", "newExercise"], ["Alt+M", "actions"], ["Alt+S", "differentRound"], ["?", "all"]];
  return (
    <div
      data-testid="plan-hint-bar"
      aria-label={t("hint.label")}
      className="sticky bottom-0 flex flex-wrap items-center gap-x-4 gap-y-1 border-t px-2 py-2 text-xs"
      style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--muted)" }}
    >
      {items.map(([keys, what]) => (
        <span key={what} className="flex items-center gap-1">
          <kbd className="rounded border px-1 font-mono" style={{ borderColor: "var(--border-strong)" }}>{keyLabel(keys, mac)}</kbd>
          {t(`hint.${what}`)}
        </span>
      ))}
      <span role="status" aria-live="polite" className="ms-auto" style={{ color: "var(--text-soft)" }}>
        {status}
      </span>
    </div>
  );
}
