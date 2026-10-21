"use client";

import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { SemanticLabel } from "@/components/semantic-label";
import { allowanceLabel } from "@/i18n/presentation";
import {
  shouldShowAllowanceQuota,
  visibleBillingAllowances,
  visibleBillingChannels,
  visibleBillingFreezes,
} from "@/components/finance/billing-entitlement-visibility";

// The member's package as one block, shared by Box › Συνδρομή and
// Εγώ › Πληρωμές (ADR-137): what they may still use, and whether access holds.

export function formatDate(uiLocale: string, value: string | null | undefined) {
  if (!value) return "—";
  return new Date(value).toLocaleDateString(uiLocale, {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

const STATUS_COLORS: Record<string, string> = {
  issued: "var(--success)",
  partially_paid: "var(--warning)",
  paid: "var(--info)",
  overdue: "var(--danger)",
  void: "var(--dim)",
  active: "var(--success)",
  inactive: "var(--dim)",
  cancelled: "var(--danger)",
  pending: "var(--warning)",
};

export function StatusBadge({ status }: { status: string }) {
  const color = STATUS_COLORS[status] ?? "var(--muted)";
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide"
      style={{ background: `${color}22`, color }}
    >
      <span
        className="inline-block w-1.5 h-1.5 rounded-full"
        style={{ background: color }}
      />
      <SemanticLabel value={status} />
    </span>
  );
}

// ─── side panel ───────────────────────────────────────────────────────────────

/** Grace slack or lost access, told plainly to the client. */
export function AccessNotice({ entitlement }: { entitlement: EffectiveEntitlement | null }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  if (!entitlement) return null;

  if (entitlement.status === "grace" && entitlement.grace_until) {
    const message =
      entitlement.source === "overdue_grace"
        ? i18n("accessGraceOverdue", { date: formatDate(uiLocale, entitlement.grace_until) })
        : i18n("accessGraceEnded", { date: formatDate(uiLocale, entitlement.grace_until) });
    return (
      <p role="status" className="rounded-2xl p-4 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", color: "var(--text)", border: "1px solid var(--warning)" }}>
        {message}
      </p>
    );
  }

  if (entitlement.status === "blocked" || (entitlement.status === "inactive" && entitlement.source !== "membership_status")) {
    return (
      <p role="alert" className="rounded-2xl p-4 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--text)", border: "1px solid var(--danger)" }}>
        {entitlement.status === "blocked" ? i18n("accessBlockedOverdue") : i18n("accessEnded")}
      </p>
    );
  }

  return null;
}

export function EntitlementCard({ entitlement }: { entitlement: EffectiveEntitlement | null }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  if (!entitlement?.plan) return null;
  const allowanceEntries = visibleBillingAllowances(entitlement.allowances);
  const channels = visibleBillingChannels(entitlement.plan.channels);
  const freezes = visibleBillingFreezes(entitlement.freezes ?? []);
  return (
    <section className="rounded-2xl p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>{i18n("yourPackageBenefitsb75c7f4")}</h2>
        <StatusBadge status={entitlement.status} />
      </div>
      {entitlement.frozen_until ? (
        <div
          className="mt-4 rounded-xl px-4 py-3"
          style={{ background: "color-mix(in srgb, var(--info) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--info) 30%, transparent)" }}
        >
          <p className="text-sm font-semibold" style={{ color: "var(--info)" }}>
            {i18n("mbPausedUntil", { date: formatDate(uiLocale, entitlement.frozen_until) })}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>{i18n("mbPausedExplainer")}</p>
        </div>
      ) : null}
      <div className="mt-4 flex flex-wrap gap-2">
        {channels.map((channel) => <span key={channel} className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }}><SemanticLabel value={channel} /></span>)}
      </div>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {allowanceEntries.map(([key, usage]) => usage ? (
          <div key={key} className="rounded-xl p-3" style={{ background: "var(--panel-muted)" }}>
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{allowanceLabel(key, i18n, entitlement.class_type_names)}</p>
            <p className="mt-1 text-2xl font-semibold" style={{ color: "var(--primary)" }}>{String(usage.remaining)}</p>
            {shouldShowAllowanceQuota(usage) ? <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("remainingOf8553660")} {String(usage.limit)} {i18n("resets5de1b0d")} {formatDate(uiLocale, usage.period_end)}</p> : null}
            {usage.extensions > 0 ? <p className="mt-1 text-xs" style={{ color: "var(--success)" }}>{i18n("includes820531f")}{usage.extensions} {i18n("personalExtension95a8d48")}</p> : null}
          </div>
        ) : null)}
      </div>
      {freezes.length > 0 ? (
        <div className="mt-4">
          <p className="text-xs font-medium uppercase tracking-wide" style={{ color: "var(--dim)" }}>{i18n("mbFreezesTitle")}</p>
          <ul className="mt-2 flex flex-col gap-1">
            {freezes.map((freeze) => (
              <li
                key={freeze.id ?? `${freeze.starts_on}-${freeze.ends_on}`}
                className="flex flex-wrap items-center justify-between gap-2 text-xs"
                style={{ color: "var(--text-soft)" }}
              >
                <span>{i18n("mbFreezeRange", { start: formatDate(uiLocale, freeze.starts_on), end: formatDate(uiLocale, freeze.ends_on) })}</span>
                {freeze.extension_days > 0 ? (
                  <span style={{ color: "var(--success)" }}>{i18n("mbFreezeExtension", { days: freeze.extension_days })}</span>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
