"use client";

import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { outcomeCounts, type GroupOutcomeRow } from "@/lib/group-variations";

/**
 * ADR-201: who got the programming and who did not, and why. A failure reads
 * exactly as it would for that person programmed alone.
 */
export function GroupOutcomeList({ rows, className = "" }: { rows: GroupOutcomeRow[]; className?: string }) {
  const i18n = useUiTranslations();
  if (!rows.length) return null;
  const { succeeded } = outcomeCounts(rows);

  return (
    <section
      className={`rounded-2xl p-4 ${className}`}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      aria-live="polite"
      data-testid="group-outcome"
    >
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {i18n("groupVariationOutcomeSummary", { succeeded, total: rows.length })}
      </p>
      <ul className="mt-2 space-y-1.5">
        {rows.map((row) => (
          <li key={row.userId} className="flex flex-wrap items-baseline gap-x-2 text-sm" data-outcome={row.ok ? "ok" : "error"}>
            <span aria-hidden="true" style={{ color: row.ok ? "var(--success)" : "var(--danger)" }}>
              {row.ok ? "✓" : "✕"}
            </span>
            <span className="font-semibold" style={{ color: "var(--text)" }}>{row.nickname}</span>
            <span style={{ color: row.ok ? "var(--muted)" : "var(--danger)" }}>
              {row.ok ? i18n("groupVariationOutcomeOk") : localizeAdminAssignmentError(row.error, i18n)}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}
