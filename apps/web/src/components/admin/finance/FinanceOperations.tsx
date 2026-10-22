"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchFinanceQueues, fetchFinanceSummary, fetchPackageCatalog, type FinanceRecord } from "@/api/finance";
import { AccountingTab } from "@/components/admin/finance/tabs/AccountingTab";
import { moduleEnabled } from "@/components/admin/finance/packages/package-catalog";
import { CorporateTab } from "@/components/admin/finance/tabs/CorporateTab";
import { MembersTab } from "@/components/admin/finance/tabs/MembersTab";
import { PackagesTab } from "@/components/admin/finance/tabs/PackagesTab";
import { PromotionsTab } from "@/components/admin/finance/tabs/PromotionsTab";
import { QueuesTab } from "@/components/admin/finance/tabs/QueuesTab";
import { ReferralsTab } from "@/components/admin/finance/tabs/ReferralsTab";
import { SeasonsTab } from "@/components/admin/finance/tabs/SeasonsTab";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { SegmentPicker } from "@/components/filters/SegmentPicker";

type Tab = "members" | "packages" | "seasons" | "promotions" | "referrals" | "queues" | "accounting" | "corporate";

export function FinanceOperations() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const accountingT = useTranslations("FinanceAccounting");
  const seasonsT = useTranslations("Seasons");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const organizationSlug = useOrganizationSlug();
  const token = tokens?.access_token;
  // ADR-098: the Corporate tab appears once the corporate_clients module is on.
  const catalogQuery = useQuery({
    queryKey: ["admin", "finance", "package-catalog"],
    enabled: Boolean(token),
    queryFn: () => fetchPackageCatalog(token!),
    staleTime: 60_000,
  });
  const corporateEnabled = catalogQuery.data ? moduleEnabled(catalogQuery.data, "corporate_clients") : false;
  const TABS: Array<{ id: Tab; label: string }> = [
    { id: "members", label: i18n("members1cb449c") },
    { id: "packages", label: i18n("packages0a99901") },
    // ADR-167: seasons are sold next to packages.
    { id: "seasons", label: seasonsT("tab") },
    { id: "promotions", label: i18n("promotions086e09b") },
    { id: "referrals", label: i18n("referrals2b0e3a3") },
    { id: "queues", label: i18n("queues83dbc32") },
    { id: "accounting", label: accountingT("tab") },
    ...(corporateEnabled ? [{ id: "corporate" as const, label: i18n("stfTabCorporate") }] : []),
  ];
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
      href: adminHref("/admin/finance?tab=queues", organizationSlug),
    },
    {
      label: i18n("pendingPaymentsb4ebfb2"),
      count: (queues.pending_payments ?? []).length,
      href: adminHref("/admin/finance?tab=queues", organizationSlug),
    },
    {
      label: i18n("referralRewards22d6a91"),
      count: (queues.pending_referral_rewards ?? []).length,
      href: adminHref("/admin/finance?tab=referrals", organizationSlug),
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
        <PageHeader
          title={i18n("financeOperations60f9e5a")}
          actions={
            <Link href={adminHref("/admin/metrics/finance", organizationSlug)} className={pageHeaderActionClass} style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
              {i18n("financeAnalytics271fe3b")}
            </Link>
          }
        />

        {summaryQuery.isLoading || queuesQuery.isLoading || attentionItems.length > 0 ? (
          <section
            aria-label={i18n("urgentFinanceAttention8b067dd")}
            className="flex flex-col gap-2 rounded-2xl p-2 sm:flex-row sm:flex-wrap sm:items-center sm:rounded-full sm:px-3"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <span className="px-2 pt-1 text-xs font-bold uppercase tracking-[0.18em] sm:pt-0" style={{ color: "var(--dim)" }}>
              {i18n("attention74e0b9c")}
            </span>
            {summaryQuery.isLoading || queuesQuery.isLoading ? (
              <span className="px-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("loading33ce417")}</span>
            ) : (
              // Phones: a full grid (two columns for an even count, one otherwise), never a sideways scroll.
              <div className={`grid gap-1.5 sm:flex sm:flex-wrap ${attentionItems.length % 2 === 0 ? "grid-cols-2" : "grid-cols-1"}`}>
                {attentionItems.map((item) => (
                  <Link
                    key={item.label}
                    className="min-w-0 truncate rounded-full px-3 py-1.5 text-center text-sm font-semibold sm:whitespace-nowrap"
                    href={item.href}
                    style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", color: "var(--danger)" }}
                  >
                    {item.label}: {item.count}
                  </Link>
                ))}
              </div>
            )}
            {Number(totals.overdue_invoice_balance_cents ?? 0) > 0 ? (
              <span className="px-2 text-xs font-semibold sm:ms-auto sm:whitespace-nowrap" style={{ color: "var(--muted)" }}>
                {i18n("overdueBalanced6ec7a8")} {money(uiLocale, totals.overdue_invoice_balance_cents)}
              </span>
            ) : null}
          </section>
        ) : null}

        {/* Tab switcher */}
        <SegmentPicker
          ariaLabel={i18n("financeOperations60f9e5a")}
          variant="track"
          value={activeTab}
          onChange={setTab}
          options={TABS.map(({ id, label }) => ({ value: id, label }))}
        />

        {/* Active tab */}
        {activeTab === "members" && <MembersTab />}
        {activeTab === "packages" && <PackagesTab />}
        {activeTab === "seasons" && <SeasonsTab />}
        {activeTab === "promotions" && <PromotionsTab />}
        {activeTab === "referrals" && <ReferralsTab />}
        {activeTab === "queues" && <QueuesTab />}
        {activeTab === "accounting" && <AccountingTab />}
        {activeTab === "corporate" && <CorporateTab />}

      </div>
    </main>
  );
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}
