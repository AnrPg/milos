"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { FinanceRecord } from "@/api/finance";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { useRecentShopSales, useShopAccess } from "@/components/shop/console/use-shop";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { orderLabel, revenueStreamRows } from "@/lib/shop/console";

const STREAM_COLOR: Record<string, string> = {
  membership: "var(--series-1)",
  package: "var(--series-2)",
  event: "var(--series-3)",
  shop: "var(--series-4)",
  other: "var(--series-neutral)",
};

/**
 * Revenue by stream (ADR-192 §2): memberships · packages · events · shop,
 * from the same payments as the headline revenue. The shop row opens the
 * shop's reports, and the latest shop sales link to their order and product.
 * Hidden until the finance summary carries the breakdown.
 */
export function RevenueStreamsCard({ summary, locationIds }: { summary: FinanceRecord | null | undefined; locationIds?: string }) {
  const t = useTranslations("ShopConsole.finance");
  const locale = useUiLocale();
  const organizationSlug = useOrganizationSlug();
  const access = useShopAccess();
  const rows = revenueStreamRows(summary);
  const recent = useRecentShopSales(locationIds, Boolean(rows) && access.sell);

  if (!rows) return null;

  return (
    <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-labelledby="revenue-streams-title" data-testid="revenue-streams">
      <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{t("eyebrow")}</p>
      <h2 id="revenue-streams-title" className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("title")}</h2>
      <ul className="mt-5 flex flex-col gap-3">
        {rows.map((row) => {
          const label = t(`streams.${row.stream}`);
          const body = (
            <>
              <span className="flex items-baseline justify-between gap-2 text-sm">
                <span style={{ color: "var(--text)" }}>{label}{row.stream === "shop" && access.analytics ? " ›" : ""}</span>
                <span className="tabular-nums" style={{ color: "var(--text-soft)" }}>{formatMoney(row.netCents, locale)} · {row.percent}%</span>
              </span>
              <span className="mt-1 block h-2 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }}>
                <span className="block h-full rounded-full" style={{ width: `${row.percent}%`, background: STREAM_COLOR[row.stream] }} />
              </span>
            </>
          );
          return (
            <li key={row.stream}>
              {row.stream === "shop" && access.analytics ? (
                <Link href={adminHref("/admin/shop?tab=analytics", organizationSlug)} className="block">
                  {body}
                </Link>
              ) : (
                <div>{body}</div>
              )}
            </li>
          );
        })}
      </ul>
      <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>{t("hint")}</p>

      {(recent.data ?? []).length > 0 ? (
        <div className="mt-5 flex flex-col gap-1" data-testid="recent-shop-sales">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("recent")}</p>
          <ul className="flex flex-col">
            {(recent.data ?? []).map((order) => {
              const first = order.lines[0];
              return (
                <li key={order.id} className="grid grid-cols-[minmax(0,1fr)_auto] items-baseline gap-3 py-2 text-sm" style={{ borderTop: "1px solid var(--border)" }}>
                  <span className="flex min-w-0 flex-col">
                    <Link href={adminHref(`/admin/shop?tab=orders&order=${order.id}`, organizationSlug)} className="truncate font-semibold" style={{ color: "var(--text)" }}>
                      {[order.invoice_number, order.channel === "pos" ? t("desk") : orderLabel(order), order.customer_name].filter(Boolean).join(" · ")}
                    </Link>
                    {first ? (
                      <Link href={adminHref(`/admin/shop/products/${first.product_id}`, organizationSlug)} className="truncate text-xs" style={{ color: "var(--muted)" }}>
                        {first.product_title}
                        {order.lines.length > 1 ? ` +${order.lines.length - 1}` : ""}
                      </Link>
                    ) : null}
                  </span>
                  <span className="tabular-nums" style={{ color: order.refunded_cents > 0 ? "var(--danger)" : "var(--text)" }}>
                    {formatMoney(order.total_cents - order.refunded_cents, locale, order.currency)}
                  </span>
                </li>
              );
            })}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
