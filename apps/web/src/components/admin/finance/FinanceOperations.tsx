"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchFinanceQueues, fetchFinanceSummary, type FinanceRecord } from "@/api/finance";
import { MembersTab } from "@/components/admin/finance/tabs/MembersTab";
import { PackagesTab } from "@/components/admin/finance/tabs/PackagesTab";
import { PromotionsTab } from "@/components/admin/finance/tabs/PromotionsTab";
import { QueuesTab } from "@/components/admin/finance/tabs/QueuesTab";
import { ReferralsTab } from "@/components/admin/finance/tabs/ReferralsTab";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

type Tab = "members" | "packages" | "promotions" | "referrals" | "queues";

export function FinanceOperations() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const TABS: Array<{ id: Tab; label: string }> = [
    { id: "members", label: i18n("members1cb449c") },
    { id: "packages", label: i18n("packages0a99901") },
    { id: "promotions", label: i18n("promotions086e09b") },
    { id: "referrals", label: i18n("referrals2b0e3a3") },
    { id: "queues", label: i18n("queues83dbc32") },
  ];
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const requestedTab = searchParams.get("tab");
  const activeTab: Tab = TABS.some(({ id }) => id === requestedTab) ? (requestedTab as Tab) : "members";

  const summaryQuery = useQuery({
    queryKey: ["admin", "finance", "summary"],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceSummary(token!),
  });

  const queuesQuery = useQuery({
    queryKey: ["admin", "finance", "queues"],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceQueues(token!, { expires_within_days: "30" }),
  });

  const totals = (summaryQuery.data?.totals ?? {}) as FinanceRecord;
  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;
  const attentionItems = [
    {
      label: i18n("overdueInvoices747a2d8"),
      count: (queues.overdue_invoices ?? []).length,
      href: "/admin/finance?tab=queues",
    },
    {
      label: i18n("pendingPaymentsb4ebfb2"),
      count: (queues.pending_payments ?? []).length,
      href: "/admin/finance?tab=queues",
    },
    {
      label: i18n("referralRewards22d6a91"),
      count: (queues.pending_referral_rewards ?? []).length,
      href: "/admin/finance?tab=referrals",
    },
  ].filter((item) => item.count > 0);

  const setTab = useCallback(
    (tab: Tab) => {
      const params = new URLSearchParams({ tab });
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router],
  );

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">

        {/* Hero */}
        <TransientHero label={i18n("financeOperationsIntroduction1d3b6fc")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("finance1b48d3f")}</p>
              <h1 className="mt-2 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
                {i18n("financeOperations60f9e5a")}
              </h1>
              <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>
                {i18n("manageMembersPackagesPromotionsReferralsAndOperationalQueues9eab02d")}
              </p>
            </div>
            <Link
              href="/admin/metrics/finance"
              className="rounded-2xl px-5 py-3 text-sm font-semibold text-center self-start"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
            >
              {i18n("financeAnalytics271fe3b")}
            </Link>
          </div>
        </section>
        </TransientHero>

        {summaryQuery.isLoading || queuesQuery.isLoading || attentionItems.length > 0 ? (
          <section
            aria-label={i18n("urgentFinanceAttention8b067dd")}
            className="flex items-center gap-2 overflow-x-auto rounded-full px-3 py-2"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <span className="shrink-0 px-2 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {i18n("attention74e0b9c")}
            </span>
            {summaryQuery.isLoading || queuesQuery.isLoading ? (
            <span className="whitespace-nowrap px-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("loading33ce417")}</span>
            ) : (
              attentionItems.map((item) => (
                <Link
                  key={item.label}
                  className="shrink-0 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-semibold"
                  href={item.href}
                  style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", color: "var(--danger)" }}
                >
                  {item.label}: {item.count}
                </Link>
              ))
            )}
            {Number(totals.overdue_invoice_balance_cents ?? 0) > 0 ? (
              <span className="ms-auto shrink-0 whitespace-nowrap px-2 text-xs font-semibold" style={{ color: "var(--muted)" }}>
                {i18n("overdueBalanced6ec7a8")} {money(uiLocale, totals.overdue_invoice_balance_cents)}
              </span>
            ) : null}
          </section>
        ) : null}

        {/* Tab switcher */}
        <div className="flex rounded-full p-0.5 self-start" style={{ background: "var(--border)" }}>
          {TABS.map(({ id, label }) => (
            <button
              key={id}
              className="rounded-full px-5 py-2 text-sm font-semibold transition-colors"
              style={
                activeTab === id
                  ? { background: "var(--text)", color: "var(--bg)" }
                  : { color: "var(--dim)" }
              }
              onClick={() => setTab(id)}
              type="button"
            >
              {label}
            </button>
          ))}
        </div>

        {/* Active tab */}
        {activeTab === "members" && <MembersTab />}
        {activeTab === "packages" && <PackagesTab />}
        {activeTab === "promotions" && <PromotionsTab />}
        {activeTab === "referrals" && <ReferralsTab />}
        {activeTab === "queues" && <QueuesTab />}

      </div>
    </main>
  );
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}
