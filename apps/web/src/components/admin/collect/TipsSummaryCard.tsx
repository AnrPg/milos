"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchTipsSummary } from "@/api/desk-collect";
import { formatMoney, KeyValue } from "@/components/fiscal/fiscal-ui";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

/**
 * ADR-272: this month's Tap to Pay tips by whom they belong to, for payroll.
 * The staff's money, not the box's revenue, so it sits apart from the
 * revenue figures.
 */
export function TipsSummaryCard() {
  const { membership } = useSelectedMembershipRole();
  if (!can(membership, "view_finance_reports") && !can(membership, "manage_billing")) return null;
  return <TipsSummary />;
}

function TipsSummary() {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const tips = useQuery({
    queryKey: ["admin", "payments", "tips", slug],
    enabled: Boolean(token),
    queryFn: () => fetchTipsSummary(token!),
  });
  const data = tips.data;

  return (
    <section className="space-y-3 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="tips-summary">
      <div>
        <h2 className="text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("tipsTitle")}</h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("tipsHint")}</p>
      </div>
      {tips.isPending ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : tips.isError ? (
        <StatusText tone="error">{localizeError(tips.error, i18n)}</StatusText>
      ) : !data || data.rows.length === 0 || !data.currency ? (
        <StatusText tone="muted">{t("tipsEmpty")}</StatusText>
      ) : (
        <div className="grid max-w-md">
          {data.rows.map((row) => (
            <KeyValue
              key={`${row.kind}:${row.user_id ?? ""}`}
              label={
                <>
                  {row.kind === "person" ? row.name : row.kind === "front_desk_role" ? t("tipsFrontDesk") : t("tipsUnattributed")}
                  <span style={{ color: "var(--muted)" }}> · {t("tipsPayments", { count: row.payments })}</span>
                </>
              }
            >
              {formatMoney(locale, row.tip_cents, data.currency!)}
            </KeyValue>
          ))}
          <KeyValue label={t("tipsTotal")} total>
            {formatMoney(locale, data.total_cents, data.currency)}
          </KeyValue>
        </div>
      )}
    </section>
  );
}
