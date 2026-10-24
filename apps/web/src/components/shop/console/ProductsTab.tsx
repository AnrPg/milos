"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import type { ShopProduct, ShopProductCounts, ShopProductStatus } from "@/api/shop-admin";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { useShopProducts } from "@/components/shop/console/use-shop";
import { ProductThumb, StockBadge, StockMeter } from "@/components/shop/shared/ShopBits";
import { inputClass, inputStyle, Pill, StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { combinationKey, priceRange, productStock, stockMeterPercent } from "@/lib/shop/console";
import { guideAnchor } from "@/lib/guides/anchors";

type Filter = "all" | ShopProductStatus | "low_stock";
const FILTERS: Filter[] = ["all", "published", "draft", "low_stock", "archived"];

export function ProductsTab({ locationIds, counts }: { locationIds?: string; counts?: ShopProductCounts }) {
  const t = useTranslations("ShopConsole.products");
  const i18n = useUiTranslations();
  const [filter, setFilter] = useState<Filter>("all");
  const [search, setSearch] = useState("");
  const products = useShopProducts(filter, locationIds);
  const needle = search.trim().toLocaleLowerCase();
  const rows = (products.data?.products ?? []).filter((product) => !needle || product.title.toLocaleLowerCase().includes(needle));

  return (
    <section {...guideAnchor("shop.products")} className="flex flex-col gap-4" aria-label={t("title")}>
      <SegmentPicker
        ariaLabel={t("filter")}
        semantics="radiogroup"
        value={filter}
        onChange={setFilter}
        options={FILTERS.map((value) => ({ value, label: t(`filters.${value}`), count: counts ? counts[value] : null }))}
      />
      <input
        type="search"
        className={inputClass}
        style={inputStyle}
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder={t("search")}
        aria-label={t("search")}
      />
      {products.isLoading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : products.error ? (
        <StatusText tone="error">{localizeError(products.error, i18n)}</StatusText>
      ) : rows.length === 0 ? (
        <StatusText tone="muted">{t("none")}</StatusText>
      ) : (
        <ul className="flex flex-col gap-2" data-testid="shop-products">
          {rows.map((product) => (
            <ProductRow key={product.id} product={product} />
          ))}
        </ul>
      )}
    </section>
  );
}

function ProductRow({ product }: { product: ShopProduct }) {
  const t = useTranslations("ShopConsole.products");
  const locale = useUiLocale();
  const organizationSlug = useOrganizationSlug();
  const stock = productStock(product);
  const range = priceRange(product.variants);
  const liveVariants = product.variants.filter((variant) => !variant.archived_at);
  const price = range ? (range.min === range.max ? formatMoney(range.min, locale) : t("from", { price: formatMoney(range.min, locale) })) : "—";
  const weakest = stock.weakest && product.options.length > 0 ? combinationKey(stock.weakest.option_values, product.options) : null;
  const statusTone = product.status === "published" ? "success" : product.status === "draft" ? "neutral" : "warning";

  return (
    <li>
      <Link
        href={adminHref(`/admin/shop/products/${product.id}`, organizationSlug)}
        className="grid grid-cols-[auto_minmax(0,1fr)] items-center gap-3 rounded-2xl p-3 sm:grid-cols-[auto_minmax(0,1fr)_10rem_auto]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <ProductThumb src={product.media[0]?.thumb_url} alt={product.title} />
        <span className="flex min-w-0 flex-col">
          <b className="truncate text-sm" style={{ color: "var(--text)" }}>{product.title}</b>
          <span className="truncate text-xs" style={{ color: "var(--muted)" }}>
            {[product.category, t("variants", { count: liveVariants.length }), price].filter(Boolean).join(" · ")}
          </span>
        </span>
        <span className="col-span-2 flex flex-col gap-1 sm:col-span-1">
          <StockMeter percent={stockMeterPercent(stock.available)} status={stock.status} label={t("stockMeter", { count: stock.available })} />
          <span className="text-xs tabular-nums" style={{ color: stock.status === "ok" ? "var(--muted)" : "var(--warning)" }}>
            {weakest && stock.weakest
              ? t("stockWeakest", { count: stock.available, variant: weakest, left: Math.max(stock.weakest.on_hand - stock.weakest.reserved, 0) })
              : t("stockUnits", { count: stock.available })}
          </span>
        </span>
        <span className="col-span-2 flex flex-wrap items-center gap-1.5 sm:col-span-1 sm:justify-end">
          {product.status === "published" && stock.status !== "ok" ? <StockBadge status={stock.status} /> : null}
          <Pill tone={statusTone}>{t(`status.${product.status}`)}</Pill>
        </span>
      </Link>
    </li>
  );
}
