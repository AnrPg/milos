"use client";

import { useFormatter, useTranslations } from "next-intl";

import type { GoalFeedbackSummary, GoalFeedbackSummarySource } from "@/api/wod-goals";

import { useGoalFeedbackSummary } from "./use-wod-goals";

/**
 * «Τι ένιωσαν» (Q6): coach totals of what members felt, for a workout or one
 * class. Counts appear only from three entries (the API decides, `shown`);
 * a read the caller may not make renders nothing.
 */
export function FeltSummaryCard({ source, className = "" }: { source: GoalFeedbackSummarySource; className?: string }) {
  const summary = useGoalFeedbackSummary(source);
  if (!summary.data) return null;
  return <FeltSummaryView summary={summary.data} className={className} />;
}

export function FeltSummaryView({ summary, className = "" }: { summary: GoalFeedbackSummary; className?: string }) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  return (
    <section
      data-testid="felt-summary"
      aria-label={t("summary.title")}
      className={`flex flex-col gap-2 rounded-2xl px-3 py-3 ${className}`}
      style={{ background: "var(--bg)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-baseline justify-between gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("summary.title")}</h3>
        <span className="text-xs" style={{ color: "var(--muted, var(--text-soft))" }}>{t("summary.entries", { count: summary.entries })}</span>
      </div>
      {!summary.shown ? (
        <p className="text-xs" style={{ color: "var(--muted, var(--text-soft))" }}>{t("summary.notShown")}</p>
      ) : (
        <>
          {summary.felt_muscles.length + summary.felt_qualities.length > 0 ? (
            <ul className="flex flex-wrap gap-1.5">
              {summary.felt_muscles.map((item) => (
                <CountChip key={item.id} label={anatomy(`muscle.${item.id}`)} count={item.count} />
              ))}
              {summary.felt_qualities.map((item) => (
                <CountChip key={item.id} label={anatomy(`quality.${item.id}`)} count={item.count} quality />
              ))}
            </ul>
          ) : null}
          {summary.goals_not_felt.length > 0 ? (
            <p className="text-xs" style={{ color: "var(--text-soft, var(--muted))" }}>
              {t("summary.notFelt", { muscles: format.list(summary.goals_not_felt.map((id) => anatomy(`muscle.${id}`))) })}
            </p>
          ) : null}
        </>
      )}
    </section>
  );
}

function CountChip({ label, count, quality = false }: { label: string; count: number; quality?: boolean }) {
  return (
    <li
      className="inline-flex min-h-8 items-center gap-1.5 rounded-full px-3 text-xs font-semibold"
      style={{
        background: quality ? "var(--panel-raised, var(--card))" : "color-mix(in srgb, var(--anatomy-felt) 18%, var(--panel))",
        border: `1px solid ${quality ? "var(--border)" : "var(--anatomy-felt)"}`,
        color: "var(--text)",
      }}
    >
      {label}
      <span className="tabular-nums" style={{ color: "var(--text-soft, var(--muted))" }}>{count}</span>
    </li>
  );
}
