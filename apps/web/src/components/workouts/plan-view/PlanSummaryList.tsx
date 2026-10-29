"use client";

import { useTranslations } from "next-intl";

import type { PlanSummaryEntry } from "./read";

/** A plan workout's sections in a list: name, flow, how many exercises. */
export function PlanSummaryList({ entries }: { entries: PlanSummaryEntry[] }) {
  const t = useTranslations("PlanView");
  return (
    <ul className="space-y-2" data-testid="plan-summary">
      {entries.map((entry, index) => (
        <li key={`${entry.name}-${index}`} className="flex min-w-0 items-center justify-between gap-4">
          <span className="min-w-0 truncate">
            {entry.name.trim() || t("untitledSection", { letter: String.fromCharCode(65 + index) })}
            <span className="ms-2 text-xs font-semibold" style={{ color: "var(--primary)" }}>
              {t(`flow.${entry.flow}`)}
            </span>
          </span>
          {entry.flow === "rest" ? null : (
            <span className="shrink-0" style={{ color: "var(--dim)" }}>
              {t("exerciseCount", { count: entry.exerciseCount })}
            </span>
          )}
        </li>
      ))}
    </ul>
  );
}
