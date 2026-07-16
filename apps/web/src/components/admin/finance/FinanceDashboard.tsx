"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { fetchFinanceQueues, fetchFinanceSummary, type FinanceRecord } from "@/api/finance";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function percent(value: unknown) {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return `${amount.toFixed(1)}%`;
}

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function dateText(value: unknown) {
  if (!value) return "—";
  return String(value).slice(0, 10);
}

function daysOverdue(dateStr: string | null | undefined): number {
  if (!dateStr) return 0;
  return Math.floor((Date.now() - new Date(dateStr).getTime()) / 86_400_000);
}

export function FinanceDashboard({ analyticsMode = false }: { analyticsMode?: boolean }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const enabled = Boolean(token);

  const summaryQuery = useQuery({
    queryKey: ["admin", "finance", "summary"],
    enabled,
    queryFn: () => fetchFinanceSummary(token!),
  });

  const queuesQuery = useQuery({
    queryKey: ["admin", "finance", "queues"],
    enabled,
    queryFn: () => fetchFinanceQueues(token!, { expires_within_days: "30" }),
  });

  const totals = (summaryQuery.data?.totals ?? {}) as FinanceRecord;
  const monthlyRevenue = (summaryQuery.data?.monthly_revenue ?? []) as FinanceRecord[];
  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;

  const kpis: Array<[string, string, string]> = [
    [i18n("activeMemberships0d117fb"), String(totals.active_memberships ?? 0), "/admin/finance"],
    [i18n("expiring30Daysbfdf986"), String(totals.expiring_memberships ?? 0), "/admin/finance?tab=queues"],
    [i18n("revenueMtd3ffc292"), money(uiLocale, totals.paid_revenue_cents), "/admin/metrics/finance"],
    [i18n("creditBalance471f025"), money(uiLocale, totals.credit_balance_cents), "/admin/finance"],
    [i18n("pendingInvoices12d9ca8"), money(uiLocale, totals.outstanding_invoice_balance_cents), "/admin/finance?tab=queues"],
    [i18n("overdueInvoices747a2d8"), money(uiLocale, totals.overdue_invoice_balance_cents), "/admin/finance?tab=queues"],
    [i18n("renewalRatef4370c2"), percent(totals.renewal_conversion_percent), "/admin/metrics/finance"],
    [i18n("invoiceCreditOffsets9fc1210"), money(uiLocale, totals.invoice_credit_offset_cents), "/admin/metrics/finance"],
  ];

  const loading = summaryQuery.isLoading;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">

        {/* Hero */}
        <TransientHero label={i18n("financeDashboardIntroduction7e0cc12")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
                {analyticsMode ? i18n("financeAnalytics107dfa1") : i18n("revenue35cf82f")}
              </p>
              <h1 className="mt-2 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
                {i18n("membershipRevenueOverview8e92aee")}
              </h1>
              <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>
                {analyticsMode
                  ? i18n("membershipRevenueRenewalAndPackageSignalsUseFinance9e261ff")
                  : i18n("readOnlyFinancialSnapshotUseFinanceOperationsFor5173cce")}
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/admin/finance"
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--text)", color: "var(--bg)" }}
              >
                {i18n("openFinanceOperationscffd9ab")}
              </Link>
              <Link
                href={analyticsMode ? "/admin/metrics" : "/admin"}
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
              >
                {analyticsMode ? i18n("analyticsMarketing0ecf7f0") : i18n("dashboard79e4071")}
              </Link>
            </div>
          </div>
        </section>
        </TransientHero>

        {/* KPIs */}
        <section className="grid gap-4 md:grid-cols-4">
          {kpis.map(([label, value, href]) => (
            <Link key={label} href={href} className="rounded-[1.9rem] p-5 transition-transform hover:-translate-y-0.5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{label}</p>
              <p className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                {loading ? "…" : value}
              </p>
            </Link>
          ))}
        </section>

        {/* Chart */}
        <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("monthlyRevenue93e061c")}</p>
          <h2 className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("paidVsPending81799fc")}</h2>
          <div className="mt-6 h-64 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={monthlyRevenue}>
                <CartesianGrid stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="period_start"
                  tickFormatter={(v) => String(v).slice(0, 7)}
                  stroke="var(--dim)"
                  tick={{ fill: "var(--dim)", fontSize: 11 }}
                />
                <YAxis
                  tickFormatter={(v) => "€" + (Number(v) / 100)}
                  stroke="var(--dim)"
                  tick={{ fill: "var(--dim)", fontSize: 11 }}
                />
                <Tooltip
                  contentStyle={{ background: "var(--panel)", border: "1px solid var(--border)", borderRadius: "1rem" }}
                  labelStyle={{ color: "var(--muted)" }}
                  itemStyle={{ color: "var(--text)" }}
                  labelFormatter={(v) => String(v).slice(0, 7)}
                  formatter={(v) => money(uiLocale, v)}
                />
                <Line dataKey="paid_revenue_cents" name="Paid" stroke="var(--primary)" strokeWidth={2.5} dot={false} />
                <Line dataKey="pending_revenue_cents" name="Pending" stroke="var(--dim)" strokeWidth={1.5} strokeDasharray="5 4" dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </section>

        {/* Queue panels 2x2 */}
        <section className="grid gap-6 md:grid-cols-2">
          <QueuePanel
            title={i18n("expiringSoon50b61e0")}
            href="/admin/finance?tab=queues"
            rows={queues.expiring_memberships ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "user_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{dateText(row.expires_on)}</span>
              </>
            )}
          />
          <QueuePanel
            title={i18n("overdueInvoices739b616")}
            href="/admin/finance?tab=queues"
            rows={queues.overdue_invoices ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "invoice_number")}</span>
                <span style={{ color: "var(--primary-strong)" }}>
                  {money(uiLocale, row.balance_due_cents)} · {daysOverdue(row.due_date as string)} {i18n("days5548ae4")}
                </span>
              </>
            )}
          />
          <QueuePanel
            title={i18n("pendingPayments9126c11")}
            href="/admin/finance?tab=queues"
            rows={queues.pending_payments ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "membership_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{money(uiLocale, row.amount_cents)}</span>
              </>
            )}
          />
          <QueuePanel
            title={i18n("pendingRewardse6d6885")}
            href="/admin/finance?tab=referrals"
            rows={queues.pending_referral_rewards ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "recipient_user_id"))}</span>
                <span style={{ color: "var(--muted)" }}><SemanticLabel value={field(row, "reward_type")} /> · {field(row, "reward_value")}</span>
              </>
            )}
          />
        </section>

      </div>
    </main>
  );
}

function QueuePanel({
  title,
  href,
  rows,
  renderRow,
}: {
  title: string;
  href: string;
  rows: FinanceRecord[];
  renderRow: (row: FinanceRecord) => React.ReactNode;
}) {
  const i18n = useUiTranslations();
  return (
    <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div
        className="sticky top-0 z-10 flex items-center justify-between gap-4 px-5 py-4"
        style={{ background: "var(--panel)", borderBottom: "1px solid var(--border)" }}
      >
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{title}</p>
        <Link
          href={href}
          className="text-xs font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {i18n("financeOps623df71")}
        </Link>
      </div>
      <div style={{ maxHeight: "18rem", overflowY: "auto" }}>
        {rows.length === 0 ? (
          <p className="px-5 py-4 text-sm" style={{ color: "var(--dim)" }}>{i18n("noItems83d7e52")}</p>
        ) : (
          rows.map((row, i) => (
            <div
              key={field(row, "id", String(i))}
              className="flex items-center justify-between gap-4 px-5 py-3 text-sm"
              style={{ borderBottom: "1px solid var(--border)" }}
            >
              {renderRow(row)}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
