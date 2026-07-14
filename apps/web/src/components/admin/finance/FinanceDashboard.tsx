"use client";

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
import { useSession } from "@/components/session-provider";

function money(cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(amount / 100);
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

export function FinanceDashboard() {
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

  const kpis: Array<[string, string]> = [
    ["Active memberships", String(totals.active_memberships ?? 0)],
    ["Expiring ≤30 days", String(totals.expiring_memberships ?? 0)],
    ["Revenue MTD", money(totals.paid_revenue_cents)],
    ["Credit balance", money(totals.credit_balance_cents)],
    ["Pending invoices", money(totals.outstanding_invoice_balance_cents)],
    ["Overdue invoices", money(totals.overdue_invoice_balance_cents)],
    ["Renewal rate", percent(totals.renewal_conversion_percent)],
    ["Invoice credit offsets", money(totals.invoice_credit_offset_cents)],
  ];

  const loading = summaryQuery.isLoading;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">

        {/* Hero */}
        <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Revenue</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                Membership revenue overview
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                Read-only financial snapshot. Use Finance Operations for management actions.
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/admin/finance/operations"
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--text)", color: "var(--bg)" }}
              >
                Open Finance Operations →
              </Link>
              <Link
                href="/admin"
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
              >
                ← Dashboard
              </Link>
            </div>
          </div>
        </section>

        {/* KPIs */}
        <section className="grid gap-4 md:grid-cols-4">
          {kpis.map(([label, value]) => (
            <article key={label} className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{label}</p>
              <p className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                {loading ? "…" : value}
              </p>
            </article>
          ))}
        </section>

        {/* Chart */}
        <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Monthly revenue</p>
          <h2 className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Paid vs pending</h2>
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
                  tickFormatter={(v) => `€${Number(v) / 100}`}
                  stroke="var(--dim)"
                  tick={{ fill: "var(--dim)", fontSize: 11 }}
                />
                <Tooltip
                  contentStyle={{ background: "var(--panel)", border: "1px solid var(--border)", borderRadius: "1rem" }}
                  labelStyle={{ color: "var(--muted)" }}
                  itemStyle={{ color: "var(--text)" }}
                  labelFormatter={(v) => String(v).slice(0, 7)}
                  formatter={(v) => money(v)}
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
            title="Expiring Soon"
            href="/admin/finance/operations?tab=queues"
            rows={queues.expiring_memberships ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "user_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{dateText(row.expires_on)}</span>
              </>
            )}
          />
          <QueuePanel
            title="Overdue Invoices"
            href="/admin/finance/operations?tab=queues"
            rows={queues.overdue_invoices ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "invoice_number")}</span>
                <span style={{ color: "var(--primary-strong)" }}>
                  {money(row.balance_due_cents)} · {daysOverdue(row.due_date as string)} days
                </span>
              </>
            )}
          />
          <QueuePanel
            title="Pending Payments"
            href="/admin/finance/operations?tab=queues"
            rows={queues.pending_payments ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "membership_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{money(row.amount_cents)}</span>
              </>
            )}
          />
          <QueuePanel
            title="Pending Rewards"
            href="/admin/finance/operations?tab=referrals"
            rows={queues.pending_referral_rewards ?? []}
            renderRow={(row) => (
              <>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "recipient_user_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{field(row, "reward_type")} · {field(row, "reward_value")}</span>
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
          Finance Ops →
        </Link>
      </div>
      <div style={{ maxHeight: "18rem", overflowY: "auto" }}>
        {rows.length === 0 ? (
          <p className="px-5 py-4 text-sm" style={{ color: "var(--dim)" }}>No items.</p>
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
