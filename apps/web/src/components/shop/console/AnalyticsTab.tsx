"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

import type { MarginRow, PricingRow } from "@/api/shop-admin";
import type { BranchFilterState } from "@/components/admin/BranchFilter";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { branchName } from "@/components/shop/console/ShopConsole";
import { useShopReport } from "@/components/shop/console/use-shop";
import { Pill, StatusText } from "@/components/staff/staff-ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import {
  changePercent,
  costCoverage,
  daysOfStockTone,
  lastComparablePriceChange,
  priceAgainstRange,
  shares,
  suggestionReasoning,
  weeklyBuckets,
} from "@/lib/shop/console";

type Range = "28" | "84" | "365";
const RANGES: Range[] = ["28", "84", "365"];

function Card({ title, hint, children, testId }: { title: string; hint?: ReactNode; children: ReactNode; testId?: string }) {
  return (
    <section className="flex min-w-0 flex-col gap-3 rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-label={title} data-testid={testId}>
      <h2 className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{title}</h2>
      {children}
      {hint ? <p className="text-xs" style={{ color: "var(--dim)" }}>{hint}</p> : null}
    </section>
  );
}

function Kpi({ value, label, href }: { value: string; label: string; href?: string }) {
  const body = (
    <>
      <b className="block text-2xl font-semibold tracking-tight tabular-nums" style={{ color: "var(--text)" }}>{value}</b>
      <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{label}</span>
    </>
  );
  const style = { background: "var(--panel)", border: "1px solid var(--border)" };
  return href ? (
    <Link href={href} className="rounded-[1.6rem] p-4" style={style}>
      {body}
    </Link>
  ) : (
    <div className="rounded-[1.6rem] p-4" style={style}>{body}</div>
  );
}

/** A share bar on the theme's series colours. */
function ShareRow({ label, value, percent, color }: { label: string; value: string; percent: number; color: string }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-baseline justify-between gap-2 text-sm">
        <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{label}</span>
        <span className="shrink-0 tabular-nums" style={{ color: "var(--text-soft)" }}>{value} · {percent}%</span>
      </div>
      <span className="block h-2 overflow-hidden rounded-full" style={{ background: "var(--panel-muted)" }}>
        <span className="block h-full rounded-full" style={{ width: `${percent}%`, background: color }} />
      </span>
    </div>
  );
}

/**
 * «Κατάστημα › Αναλυτικά» (ADR-192 §4): sales by week net of discounts and
 * refunds, top products with margin where cost is known, app vs desk, by
 * branch, stock value and low stock, attribution, and per-variant pricing
 * indicators with an advisory price range.
 */
export function AnalyticsTab({ locationIds, branchFilter }: { locationIds?: string; branchFilter: BranchFilterState }) {
  const t = useTranslations("ShopConsole.analytics");
  const locale = useUiLocale();
  const organizationSlug = useOrganizationSlug();
  const [range, setRange] = useState<Range>("84");
  const window = { days: Number(range), locationIds };
  const sales = useShopReport("sales", window);
  const products = useShopReport("products", window);
  const margin = useShopReport("margin", window);
  const channels = useShopReport("channels", window);
  const inventory = useShopReport("inventory", window);
  const attribution = useShopReport("attribution", window);
  const pricing = useShopReport("pricing", window);
  const money = (cents: number | null | undefined) => formatMoney(cents ?? 0, locale);
  const today = new Date().toISOString().slice(0, 10);

  const totals = sales.data?.totals;
  const change = totals ? changePercent(totals.net_cents, sales.data?.previous_totals?.net_cents) : null;
  const weeks = sales.data ? weeklyBuckets(sales.data.days, today) : [];
  const marginRows = margin.data?.products ?? [];
  const coverage = costCoverage(marginRows);
  const marginById = new Map<string, MarginRow>(marginRows.map((row) => [row.product_id, row]));
  const units = (products.data?.products_by_units ?? []).reduce((sum, row) => sum + row.net_units, 0);

  if (sales.isLoading) return <StatusText tone="muted">{t("loading")}</StatusText>;
  if (sales.error) return <StatusText tone="muted">{t("unavailable")}</StatusText>;

  return (
    <section className="flex flex-col gap-5" aria-label={t("title")} data-testid="shop-analytics">
      <SegmentPicker ariaLabel={t("range")} semantics="radiogroup" value={range} onChange={setRange} options={RANGES.map((value) => ({ value, label: t(`ranges.${value}`) }))} />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi value={money(totals?.net_cents)} label={change === null ? t("kpi.sales") : t("kpi.salesChange", { change })} />
        <Kpi
          value={margin.data?.totals.margin_percent === null || margin.data?.totals.margin_percent === undefined ? "—" : `${Math.round(margin.data.totals.margin_percent)}%`}
          label={t("kpi.margin", { costed: coverage.costed, total: coverage.total })}
        />
        <Kpi value={String(units)} label={t("kpi.units", { orders: totals?.orders ?? 0 })} />
        <Kpi
          value={money(inventory.data?.totals.stock_value_cents)}
          label={t("kpi.stockValue", { count: inventory.data?.totals.low_stock_count ?? 0 })}
          href={adminHref("/admin/shop?tab=stock", organizationSlug)}
        />
      </div>

      <Card title={t("weekly")} hint={t("weeklyHint")} testId="shop-sales-chart">
        {weeks.length === 0 ? (
          <StatusText tone="muted">{t("noSales")}</StatusText>
        ) : (
          <div className="h-56 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={weeks}>
                <CartesianGrid stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="weekStart"
                  tickFormatter={(value) => new Date(`${value}T00:00:00`).toLocaleDateString(locale, { day: "numeric", month: "numeric" })}
                  stroke="var(--dim)"
                  tick={{ fill: "var(--dim)", fontSize: 11 }}
                />
                <YAxis tickFormatter={(value) => formatMoney(Number(value), locale).replace(/[.,]00(?=\D*$)/, "")} stroke="var(--dim)" tick={{ fill: "var(--dim)", fontSize: 11 }} width={64} />
                <Tooltip
                  cursor={{ fill: "var(--panel-muted)" }}
                  contentStyle={{ background: "var(--panel)", border: "1px solid var(--border)", borderRadius: "1rem" }}
                  labelStyle={{ color: "var(--muted)" }}
                  itemStyle={{ color: "var(--text)" }}
                  labelFormatter={(value) => t("weekOf", { date: new Date(`${value}T00:00:00`).toLocaleDateString(locale, { dateStyle: "medium" }) })}
                  formatter={(value) => [money(Number(value)), t("net")]}
                />
                <Bar dataKey="netCents" radius={[6, 6, 0, 0]}>
                  {weeks.map((week) => (
                    <Cell key={week.weekStart} fill="var(--series-1)" fillOpacity={week.partial ? 0.45 : 1} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </Card>

      <Card title={t("top")} hint={t("marginHint")} testId="shop-top-products">
        {(products.data?.products_by_revenue ?? []).length === 0 ? (
          <StatusText tone="muted">{t("noSales")}</StatusText>
        ) : (
          <table className="w-full table-fixed text-sm">
            <thead>
              <tr style={{ color: "var(--muted)" }}>
                <th className="w-1/2 py-1 text-start font-semibold">{t("product")}</th>
                <th className="py-1 text-end font-semibold">{t("units")}</th>
                <th className="py-1 text-end font-semibold">{t("revenue")}</th>
                <th className="py-1 text-end font-semibold">{t("marginCol")}</th>
              </tr>
            </thead>
            <tbody>
              {(products.data?.products_by_revenue ?? []).slice(0, 8).map((row) => {
                const rowMargin = marginById.get(row.product_id);
                return (
                  <tr key={row.product_id} style={{ borderTop: "1px solid var(--border)", color: "var(--text)" }}>
                    <td className="truncate py-2 pe-2">
                      <Link href={adminHref(`/admin/shop/products/${row.product_id}`, organizationSlug)} style={{ color: "var(--text)" }}>
                        {row.product_name}
                      </Link>
                    </td>
                    <td className="py-2 text-end tabular-nums">{row.net_units}</td>
                    <td className="py-2 text-end tabular-nums">{money(row.net_revenue_cents)}</td>
                    <td className="py-2 text-end tabular-nums">{rowMargin && rowMargin.margin_percent !== null && rowMargin.costed_revenue_cents > 0 ? `${Math.round(rowMargin.margin_percent)}%` : "—"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </Card>

      <div className="grid gap-5 md:grid-cols-2">
        <Card title={t("channels")}>
          {shares(channels.data?.by_channel ?? [], (row) => row.net_revenue_cents).map(({ row, percent }, index) => (
            <ShareRow key={row.channel} label={t(`channel.${row.channel}`)} value={money(row.net_revenue_cents)} percent={percent} color={index === 0 ? "var(--series-1)" : "var(--series-3)"} />
          ))}
          {(channels.data?.by_channel ?? []).length === 0 ? <StatusText tone="muted">{t("noSales")}</StatusText> : null}
        </Card>
        {branchFilter.visible ? (
          <Card title={t("branches")}>
            {shares(channels.data?.by_location ?? [], (row) => row.net_revenue_cents).map(({ row, percent }, index) => (
              <ShareRow
                key={row.location_id ?? "none"}
                label={branchName(branchFilter, row.location_id) ?? t("noBranch")}
                value={money(row.net_revenue_cents)}
                percent={percent}
                color={`var(--series-${(index % 8) + 1})`}
              />
            ))}
          </Card>
        ) : null}
        <Card title={t("attribution")} hint={t("attributionHint")} testId="shop-attribution">
          <ul className="flex flex-col gap-1.5 text-sm">
            {(attribution.data?.by_source ?? []).map((row) => (
              <li key={`${row.source}-${row.source_ref_id ?? ""}`} className="flex items-baseline justify-between gap-2">
                <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{row.label ? `${t(`source.${row.source}`)} · ${row.label}` : t(`source.${row.source}`)}</span>
                <span className="shrink-0 tabular-nums" style={{ color: "var(--text-soft)" }}>{t("ordersMoney", { count: row.orders, amount: money(row.net_revenue_cents) })}</span>
              </li>
            ))}
            {(attribution.data?.by_promotion_code ?? []).map((row) => (
              <li key={row.promotion_code} className="flex items-baseline justify-between gap-2">
                <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{t("codeRow", { code: row.promotion_code })}</span>
                <span className="shrink-0 tabular-nums" style={{ color: "var(--text-soft)" }}>{t("ordersMoney", { count: row.orders, amount: money(row.net_revenue_cents) })}</span>
              </li>
            ))}
          </ul>
          {attribution.data ? (
            <p className="text-xs" style={{ color: "var(--muted)" }}>
              {t("unattributed", { count: attribution.data.unattributed.orders, amount: money(attribution.data.unattributed.net_revenue_cents) })}
            </p>
          ) : null}
        </Card>
        <Card title={t("lowStock")} testId="shop-low-stock">
          {(inventory.data?.low_stock ?? []).length === 0 ? (
            <StatusText tone="muted">{t("noLowStock")}</StatusText>
          ) : (
            <ul className="flex flex-col gap-1.5 text-sm">
              {(inventory.data?.low_stock ?? []).slice(0, 6).map((item) => (
                <li key={`${item.variant_id}-${item.location_id ?? ""}`} className="flex items-baseline justify-between gap-2">
                  <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{[item.product_name, item.variant_name].filter(Boolean).join(" · ")}</span>
                  <span className="shrink-0 tabular-nums" style={{ color: "var(--warning)" }}>{t("left", { count: item.available })}</span>
                </li>
              ))}
            </ul>
          )}
          <Link href={adminHref("/admin/shop?tab=stock", organizationSlug)} className="text-xs font-semibold" style={{ color: "var(--primary)" }}>
            {t("openStock")}
          </Link>
        </Card>
      </div>

      <Card title={t("pricing.title")} hint={t("pricing.hint")} testId="shop-pricing">
        {pricing.isLoading ? (
          <StatusText tone="muted">{t("loading")}</StatusText>
        ) : (pricing.data?.variants ?? []).length === 0 ? (
          <StatusText tone="muted">{t("pricing.none")}</StatusText>
        ) : (
          <ul className="flex flex-col gap-2">
            {(pricing.data?.variants ?? []).map((row) => (
              <PricingItem key={row.variant_id} row={row} />
            ))}
          </ul>
        )}
      </Card>
    </section>
  );
}

function Indicator({ label, value, tone = "neutral" }: { label: string; value: string; tone?: "neutral" | "warning" | "danger" }) {
  const color = tone === "danger" ? "var(--danger)" : tone === "warning" ? "var(--warning)" : "var(--text)";
  return (
    <div className="flex min-w-0 flex-col">
      <dt className="text-[11px] font-semibold uppercase tracking-[0.12em]" style={{ color: "var(--dim)" }}>{label}</dt>
      <dd className="tabular-nums text-sm" style={{ color }}>{value}</dd>
    </div>
  );
}

function PricingItem({ row }: { row: PricingRow }) {
  const t = useTranslations("ShopConsole.analytics.pricing");
  const locale = useUiLocale();
  const money = (cents: number | null | undefined) => (cents === null || cents === undefined ? "—" : formatMoney(cents, locale));
  const pct = (value: number | null | undefined) => (value === null || value === undefined ? "—" : `${Math.round(value)}%`);
  const num = (value: number | null | undefined) => (value === null || value === undefined ? "—" : new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value));
  const reasoning = suggestionReasoning(row.suggested_price);
  const change = lastComparablePriceChange(row);
  const position = priceAgainstRange(row);
  const suggested = row.suggested_price;
  const name = [row.product_name, row.variant_name].filter(Boolean).join(" · ");

  return (
    <li className="rounded-2xl" style={{ background: "var(--panel-muted)" }}>
      <details>
        <summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-2 p-3">
          <span className="flex min-w-0 flex-col">
            <b className="truncate text-sm" style={{ color: "var(--text)" }}>{name}</b>
            <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>
              {[money(row.price_cents), row.margin_percent !== null ? t("marginShort", { margin: Math.round(row.margin_percent) }) : t("noCost"), t("perWeek", { value: num(row.velocity_per_week) })].join(" · ")}
            </span>
          </span>
          {position ? <Pill tone={position === "within" ? "success" : "warning"}>{t(`position.${position}`)}</Pill> : null}
        </summary>
        <div className="flex flex-col gap-3 px-3 pb-3">
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Indicator label={t("margin")} value={pct(row.margin_percent)} />
            <Indicator label={t("markup")} value={pct(row.markup_percent)} />
            <Indicator label={t("sellThrough")} value={pct(row.sell_through_percent)} />
            <Indicator label={t("daysOfStock")} value={num(row.days_of_stock_left)} tone={daysOfStockTone(row.days_of_stock_left)} />
            <Indicator label={t("velocity")} value={num(row.velocity_per_week)} />
            <Indicator label={t("sold")} value={String(row.units_sold)} />
            <Indicator
              label={t("discountEffect")}
              value={row.discount && row.discount.volume_lift_percent !== null ? t("lift", { change: Math.round(row.discount.volume_lift_percent), share: Math.round(row.discount.promo_unit_share_percent ?? 0) }) : "—"}
            />
            <Indicator
              label={t("priceChange")}
              value={
                change
                  ? t("velocityChange", { from: money(change.from_price_cents), to: money(change.to_price_cents), before: num(change.velocity_before), after: num(change.velocity_after) })
                  : "—"
              }
            />
          </dl>
          <div className="flex flex-col gap-1 rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex flex-wrap items-center gap-2">
              <b className="text-sm" style={{ color: "var(--text)" }}>{t("suggested")}</b>
              <Pill tone="neutral">{t("advisory")}</Pill>
            </div>
            <p className="text-sm tabular-nums" style={{ color: "var(--text)" }}>
              {suggested.low_cents !== null && suggested.high_cents !== null ? t("range", { low: money(suggested.low_cents), high: money(suggested.high_cents) }) : t("noRange")}
            </p>
            <ul className="flex flex-col gap-0.5 text-xs" style={{ color: "var(--muted)" }} aria-label={t("inputs")}>
              {reasoning.costKnown ? (
                <li>
                  {t("inputCostPlus", {
                    cost: money(suggested.inputs.cost_cents),
                    margin: reasoning.targetMarginPercent,
                    source: t(reasoning.targetFromCategory ? "sourceCategory" : "sourceDefault"),
                  })}
                </li>
              ) : (
                <li>{t("inputNoCost")}</li>
              )}
              <li>{t(`pace.${reasoning.pace}`, { velocity: num(suggested.inputs.velocity_per_week), median: num(suggested.inputs.category_median_velocity_per_week) })}</li>
              {reasoning.priceSensitive ? <li>{t("priceSensitive")}</li> : null}
              <li>{t("yourCall")}</li>
            </ul>
          </div>
        </div>
      </details>
    </li>
  );
}
