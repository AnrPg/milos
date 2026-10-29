"use client";

import { useTranslations } from "next-intl";

import type { PlanWizardStep } from "@/stores/structured-plan";

import { KEYS, keyLabel } from "./keymap";

type HintKey = "section" | "open" | "newSection" | "all" | "search" | "choose" | "continue" | "close" | "nextField" | "nextStep" | "back" | "newExercise" | "actions" | "differentRound" | "score";

/**
 * One quiet line with the few keys that matter where the coach is; «?»
 * lists the rest.
 */
export function HintBar({ open, step, mac, status }: { open: boolean; step: PlanWizardStep; mac: boolean; status: string | null }) {
  const t = useTranslations("PlanEditor");
  const items: [string, HintKey][] = !open
    ? [[KEYS.arrows, "section"], [KEYS.enter, "open"], [KEYS.newSection, "newSection"], [KEYS.sheet, "all"]]
    : step === 0
      ? [[KEYS.arrows, "choose"], [KEYS.enter, "continue"], [KEYS.esc, "close"]]
      : step !== 2
        ? [[KEYS.tab, "nextField"], [KEYS.enter, "nextStep"], [KEYS.back, "back"], [KEYS.esc, "close"]]
        : [[KEYS.enter, "newExercise"], [KEYS.actions, "actions"], [KEYS.differentRound, "differentRound"], [KEYS.sheet, "all"]];
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
