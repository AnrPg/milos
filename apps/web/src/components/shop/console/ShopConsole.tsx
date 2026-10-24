"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { useTranslations } from "next-intl";

import { BranchFilterControl, BranchFilterNote, useBranchFilter, type BranchFilterState } from "@/components/admin/BranchFilter";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { AnalyticsTab } from "@/components/shop/console/AnalyticsTab";
import { OrdersTab } from "@/components/shop/console/OrdersTab";
import { ProductsTab } from "@/components/shop/console/ProductsTab";
import { ShopEmptyState } from "@/components/shop/console/ShopEmptyState";
import { StockTab } from "@/components/shop/console/StockTab";
import { useShopAccess, useShopOrders, useShopProducts } from "@/components/shop/console/use-shop";
import { StatusText } from "@/components/staff/staff-ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { guideAnchor } from "@/lib/guides/anchors";
import { GuideButton } from "@/components/guides/GuideButton";

export type ShopTab = "products" | "orders" | "stock" | "analytics";
const TABS: ShopTab[] = ["products", "orders", "stock", "analytics"];

/** Branch names by id, for rows that carry a branch. */
export function branchName(filter: BranchFilterState, locationId: string | null | undefined) {
  if (!locationId) return null;
  return filter.locations.find((location) => location.id === locationId)?.name ?? null;
}

/**
 * Κονσόλα › «Κατάστημα» (shop proposal §2, option A): Προϊόντα · Παραγγελίες
 * · Απόθεμα · Αναλυτικά, with «Ταμείο» and «+ Νέο προϊόν» in the header and a
 * 3-step checklist while the catalog is empty. Every tab follows the page
 * branch filter (ADR-186 §7), shown to staff who see two or more branches.
 */
export function ShopConsole() {
  const t = useTranslations("ShopConsole");
  const router = useRouter();
  const searchParams = useSearchParams();
  const organizationSlug = useOrganizationSlug();
  const access = useShopAccess();
  const branchFilter = useBranchFilter("shop");
  const locationIds = branchFilter.param;

  const tabs = TABS.filter((tab) => (tab === "analytics" ? access.analytics : tab === "orders" ? access.sell : access.manage));
  const requested = searchParams.get("tab") as ShopTab | null;
  const activeTab: ShopTab = requested && tabs.includes(requested) ? requested : tabs[0] ?? "products";

  const products = useShopProducts("all", locationIds);
  const placed = useShopOrders("placed", locationIds);
  const counts = products.data?.counts;
  const placedCount = placed.data?.counts?.placed ?? 0;
  const empty = access.manage && counts !== undefined && counts.all === 0;
  const open = (counts?.published ?? 0) > 0;

  const setTab = useCallback(
    (tab: ShopTab) => router.replace(`?${new URLSearchParams({ tab }).toString()}`, { scroll: false }),
    [router],
  );

  if (access.isLoading) {
    return (
      <Shell>
        <StatusText tone="muted">{t("loading")}</StatusText>
      </Shell>
    );
  }
  if (!access.any) {
    return (
      <Shell>
        <PageHeader title={t("title")} />
        <StatusText tone="muted">{t("noAccess")}</StatusText>
      </Shell>
    );
  }

  return (
    <Shell>
      <PageHeader
        title={
          <span className="inline-flex flex-wrap items-baseline gap-x-3">
            {t("title")}
            {counts ? (
              <span className="text-sm font-semibold" style={{ color: open ? "var(--success)" : "var(--dim)" }} data-testid="shop-open-state">
                {open ? t("openState", { count: counts.published }) : t("closedState")}
              </span>
            ) : null}
          </span>
        }
        actions={
          <>
            <BranchFilterControl filter={branchFilter} />
            <GuideButton guide="shop_staff" />
            {access.sell && !empty ? (
              <Link {...guideAnchor("shop.pos")} href={adminHref("/admin/shop/pos", organizationSlug)} className={pageHeaderActionClass} style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
                {t("pos.title")}
              </Link>
            ) : null}
            {access.manage ? (
              <Link {...guideAnchor("shop.newProduct")} href={adminHref("/admin/shop/products/new", organizationSlug)} className={pageHeaderActionClass} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                + {t("newProduct")}
              </Link>
            ) : null}
          </>
        }
      />

      {empty ? (
        <ShopEmptyState />
      ) : (
        <>
          {tabs.length > 1 ? (
            <SegmentPicker
              guide="shop.tabs"
              ariaLabel={t("title")}
              variant="track"
              stretch
              value={activeTab}
              onChange={setTab}
              options={tabs.map((tab) => ({ value: tab, label: t(`tabs.${tab}`), count: tab === "orders" && placedCount > 0 ? placedCount : null }))}
            />
          ) : null}
          {locationIds ? <BranchFilterNote>{t("branchNote")}</BranchFilterNote> : null}

          {activeTab === "products" ? <ProductsTab locationIds={locationIds} counts={counts} /> : null}
          {activeTab === "orders" ? <OrdersTab locationIds={locationIds} branchFilter={branchFilter} /> : null}
          {activeTab === "stock" ? <StockTab locationIds={locationIds} branchFilter={branchFilter} /> : null}
          {activeTab === "analytics" ? <AnalyticsTab locationIds={locationIds} branchFilter={branchFilter} /> : null}
        </>
      )}
    </Shell>
  );
}

export function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-6xl flex-col gap-6">{children}</div>
    </main>
  );
}
