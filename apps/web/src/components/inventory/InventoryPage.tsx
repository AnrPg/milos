"use client";

import { useRouter, useSearchParams } from "next/navigation";

import { InventoryReportView } from "@/components/inventory/InventoryReportView";
import { inventoryTab, loggableEventKinds, type InventoryTab } from "@/components/inventory/inventory-helpers";
import { MachinesTab } from "@/components/inventory/MachinesTab";
import { SuppliesTab } from "@/components/inventory/SuppliesTab";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

/** `/admin/inventory`: machines and their log, consumables and their stock (ADR-104). */
export function InventoryPage() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const { membership, isLoading } = useSelectedMembershipRole();
  const canManage = can(membership, "manage_inventory");
  const canReport = canManage || can(membership, "report_inventory");
  const tab = inventoryTab(searchParams.get("tab"), canManage);
  const kinds = loggableEventKinds(membership);

  const setTab = (next: InventoryTab) => router.replace(`?${new URLSearchParams({ tab: next }).toString()}`, { scroll: false });

  const tabs: Array<{ id: InventoryTab; label: string }> = [
    { id: "machines", label: i18n("invTabMachines") },
    { id: "supplies", label: i18n("invTabSupplies") },
  ];

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl flex-col gap-5">
        <header>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
            {i18n("invEyebrow")}
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
            {i18n("invTitle")}
          </h1>
          <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
            {canManage ? i18n("invIntroManager") : i18n("invIntroReporter")}
          </p>
        </header>

        {!token || isLoading ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : !canReport ? (
          <StatusText tone="muted">{i18n("invNoAccess")}</StatusText>
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div role="tablist" aria-label={i18n("invEyebrow")} className="flex rounded-full p-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                {tabs.map((option) => {
                  const active = tab === option.id;
                  return (
                    <button
                      key={option.id}
                      type="button"
                      role="tab"
                      aria-selected={active}
                      className="rounded-full px-4 py-2 text-sm font-semibold"
                      style={active ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { color: "var(--text-soft)" }}
                      onClick={() => setTab(option.id)}
                    >
                      {option.label}
                    </button>
                  );
                })}
              </div>
              {canManage ? (
                <button
                  type="button"
                  aria-pressed={tab === "report"}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold"
                  style={
                    tab === "report"
                      ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                      : { background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }
                  }
                  onClick={() => setTab("report")}
                >
                  {i18n("invTabReport")}
                </button>
              ) : null}
            </div>

            {tab === "machines" ? <MachinesTab token={token} canManage={canManage} kinds={kinds} /> : null}
            {tab === "supplies" ? <SuppliesTab token={token} canManage={canManage} /> : null}
            {tab === "report" ? <InventoryReportView token={token} /> : null}
          </>
        )}
      </div>
    </main>
  );
}
