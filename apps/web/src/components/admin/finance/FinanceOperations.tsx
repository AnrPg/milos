"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { MembersTab } from "@/components/admin/finance/tabs/MembersTab";
import { PackagesTab } from "@/components/admin/finance/tabs/PackagesTab";
import { PromotionsTab } from "@/components/admin/finance/tabs/PromotionsTab";
import { QueuesTab } from "@/components/admin/finance/tabs/QueuesTab";
import { ReferralsTab } from "@/components/admin/finance/tabs/ReferralsTab";

type Tab = "members" | "packages" | "promotions" | "referrals" | "queues";

const TABS: Array<{ id: Tab; label: string }> = [
  { id: "members", label: "Members" },
  { id: "packages", label: "Packages" },
  { id: "promotions", label: "Promotions" },
  { id: "referrals", label: "Referrals" },
  { id: "queues", label: "Queues" },
];

export function FinanceOperations() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const activeTab = (searchParams.get("tab") as Tab | null) ?? "members";

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
        <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Revenue</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                Finance Operations
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                Manage members, packages, promotions, referrals, and operational queues.
              </p>
            </div>
            <Link
              href="/admin/finance"
              className="rounded-2xl px-5 py-3 text-sm font-semibold text-center self-start"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
            >
              ← Finance Dashboard
            </Link>
          </div>
        </section>

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
