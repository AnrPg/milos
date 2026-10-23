"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

import type { ShopProductSummary } from "@/api/shop";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { cartUnits } from "@/lib/shop/cart";
import {
  NO_FILTERS,
  drawerFilterCount,
  filterProducts,
  filtersFromParams,
  filtersToParams,
  orderReference,
  shopCategories,
  sortOpenOrders,
  type ShopFilters,
} from "@/lib/shop/catalog";
import { productCard } from "@/lib/shop/variants";

import { CartButton, ErrorNotice, FlagPill, LoadingLine, Money, ProductPhoto, ShopHeader } from "./ShopParts";
import { shopHref, useCart, useShopBox, useShopProducts, useStorefront } from "./use-shop";

const ALL = "__all";
const scrollKey = (slug: string) => `palee:shop-scroll:${slug}`;

/**
 * Box › Κατάστημα: a two-column grid, a photo and the price on every card,
 * one card per product with its colours merged in. «Φίλτρα (n)» stays first
 * in a fixed row with the category chips (no sideways scroll); the filters
 * live in the URL and the scroll position is put back on return from a
 * product (Baymard PLP). Open orders sit at the top, ready ones first.
 */
export function ShopPage() {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { slug, name, explicit, isLoading } = useShopBox();
  const storefront = useStorefront(slug);
  const products = useShopProducts(slug);
  const { cart } = useCart(slug);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const filters = filtersFromParams(new URLSearchParams(searchParams.toString()));
  const list = useMemo(() => products.data ?? [], [products.data]);
  const categories = useMemo(() => shopCategories(list), [list]);
  const shown = useMemo(() => filterProducts(list, filters), [list, filters]);
  const shop = storefront.data;
  const restored = useRef(false);

  // Back from a product: the same place in the list.
  useEffect(() => {
    if (restored.current || !slug || !products.data) return;
    restored.current = true;
    try {
      const saved = window.sessionStorage.getItem(scrollKey(slug));
      if (saved) {
        window.sessionStorage.removeItem(scrollKey(slug));
        window.requestAnimationFrame(() => window.scrollTo({ top: Number(saved) || 0 }));
      }
    } catch {
      // No session storage: the list opens at the top.
    }
  }, [products.data, slug]);

  function rememberScroll() {
    if (!slug) return;
    try {
      window.sessionStorage.setItem(scrollKey(slug), String(Math.round(window.scrollY)));
    } catch {
      // Nothing to restore later.
    }
  }

  function applyFilters(next: ShopFilters) {
    const params = filtersToParams(next, new URLSearchParams(searchParams.toString()));
    const qs = params.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  }

  const openOrders = sortOpenOrders(shop?.open_orders ?? []);
  const subtitle = [name, shop?.pickup_locations.length === 1 ? t("pickupAt", { place: shop.pickup_locations[0].name }) : null]
    .filter(Boolean)
    .join(" · ");
  const extraFilters = drawerFilterCount(filters);

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <ShopHeader
        backHref="/box"
        backLabel={t("backToBox")}
        title={t("title")}
        subtitle={subtitle || null}
        end={<CartButton href={shopHref("/cart", slug, explicit)} units={cartUnits(cart)} />}
      />

      {openOrders.map((order) => (
        <Link
          key={order.id}
          href={shopHref(`/orders/${encodeURIComponent(order.id)}`, slug, explicit)}
          className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 text-sm font-bold"
          style={{
            background: "var(--panel)",
            border: `1px solid ${order.status === "ready_for_pickup" ? "var(--primary)" : "var(--border)"}`,
            color: "var(--text)",
          }}
          data-testid="shop-open-order"
        >
          <span className="truncate">
            {order.status === "ready_for_pickup"
              ? t("orderReadyLink", { number: orderReference(order) })
              : t("orderPlacedLink", { number: orderReference(order) })}
          </span>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </Link>
      ))}

      {isLoading || products.isLoading ? (
        <LoadingLine />
      ) : products.isError ? (
        <ErrorNotice message={t("loadFailed")} />
      ) : list.length === 0 ? (
        <p className="rounded-3xl px-5 py-8 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t("empty")}
        </p>
      ) : (
        <>
          <div className="flex items-start gap-2">
            <button
              type="button"
              onClick={() => setFiltersOpen(true)}
              className="inline-flex min-h-10 shrink-0 items-center gap-1.5 rounded-xl px-3.5 text-sm font-bold"
              style={{ background: "var(--panel)", border: `1px solid ${extraFilters > 0 ? "var(--text)" : "var(--border)"}`, color: "var(--text)" }}
              aria-haspopup="dialog"
            >
              {t("filters", { count: extraFilters })}
            </button>
            {categories.length > 0 ? (
              <SegmentPicker
                className="min-w-0 flex-1"
                ariaLabel={t("categories")}
                semantics="radiogroup"
                value={filters.category ?? ALL}
                onChange={(value) => applyFilters({ ...filters, category: value === ALL ? null : value })}
                options={[{ value: ALL, label: t("all") }, ...categories.map((category) => ({ value: category, label: category }))]}
              />
            ) : null}
          </div>

          {shown.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-6 text-center">
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noMatch")}</p>
              <button type="button" onClick={() => applyFilters(NO_FILTERS)} className="min-h-11 text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
                {t("clearFilters")}
              </button>
            </div>
          ) : (
            <ul className="grid grid-cols-2 gap-3" data-testid="shop-grid">
              {shown.map((product) => (
                <li key={product.id}>
                  <ProductCardLink
                    product={product}
                    href={shopHref(`/product/${encodeURIComponent(product.id)}`, slug, explicit)}
                    locale={locale}
                    onOpen={rememberScroll}
                  />
                </li>
              ))}
            </ul>
          )}

          {shop?.member_discount_percent ? (
            <p className="text-center text-sm" style={{ color: "var(--text-soft)" }}>
              {t("memberDiscountNote", { percent: shop.member_discount_percent })}
            </p>
          ) : null}
        </>
      )}

      {filtersOpen ? <FiltersDialog filters={filters} onApply={applyFilters} onClose={() => setFiltersOpen(false)} /> : null}
    </main>
  );
}

function ProductCardLink({ product, href, locale, onOpen }: { product: ShopProductSummary; href: string; locale: string; onOpen: () => void }) {
  const t = useTranslations("Shop");
  const card = productCard(product);
  const variantsLine =
    card.colours.length > 1
      ? t("colourCount", { count: card.colours.length })
      : card.sizeCount > 1
        ? t("sizeCount", { count: card.sizeCount })
        : null;
  return (
    <Link href={href} onClick={onOpen} className="flex flex-col gap-1.5" data-testid="shop-product-card">
      <ProductPhoto photo={product.photos[0]} title={product.title} className={card.soldOut ? "opacity-60" : ""}>
        {card.flag ? (
          <span className="absolute start-2 top-2">
            <FlagPill flag={card.flag} />
          </span>
        ) : null}
      </ProductPhoto>
      <span className="line-clamp-2 text-sm font-bold" style={{ color: "var(--text)" }}>
        {product.title}
      </span>
      {variantsLine ? (
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {variantsLine}
        </span>
      ) : null}
      {card.fromPriceCents !== null && card.currency ? (
        <span className="text-sm font-extrabold" style={{ color: "var(--text)" }}>
          {card.hasPriceRange ? (
            t("fromPrice", { price: new Intl.NumberFormat(locale, { style: "currency", currency: card.currency }).format(card.fromPriceCents / 100) })
          ) : (
            <Money cents={card.fromPriceCents} currency={card.currency} locale={locale} />
          )}
        </span>
      ) : null}
    </Link>
  );
}

function FiltersDialog({ filters, onApply, onClose }: { filters: ShopFilters; onApply: (filters: ShopFilters) => void; onClose: () => void }) {
  const t = useTranslations("Shop");
  const [draft, setDraft] = useState(filters);
  return (
    <Dialog
      onClose={onClose}
      title={t("filtersTitle")}
      variant="sheet"
      size="md"
      footer={
        <div className="flex w-full gap-2">
          <DialogButton onClick={() => setDraft({ ...NO_FILTERS, category: draft.category })}>{t("clearFilters")}</DialogButton>
          <DialogButton
            tone="primary"
            onClick={() => {
              onApply(draft);
              onClose();
            }}
          >
            {t("showResults")}
          </DialogButton>
        </div>
      }
    >
      <div className="flex flex-col gap-2">
        <ToggleRow label={t("filterInStock")} checked={draft.inStockOnly} onChange={(inStockOnly) => setDraft({ ...draft, inStockOnly })} />
        <ToggleRow label={t("filterNew")} checked={draft.newOnly} onChange={(newOnly) => setDraft({ ...draft, newOnly })} />
      </div>
    </Dialog>
  );
}

function ToggleRow({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex min-h-12 w-full items-center justify-between gap-3 rounded-2xl px-4 text-start text-sm font-semibold"
      style={{ background: "var(--panel-raised)", border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
    >
      {label}
      <span
        aria-hidden="true"
        className="relative inline-block h-6 w-11 rounded-full transition-colors"
        style={{ background: checked ? "var(--primary)" : "var(--border)" }}
      >
        <span
          className="absolute top-0.5 h-5 w-5 rounded-full transition-all"
          style={{ background: "var(--panel)", insetInlineStart: checked ? "1.375rem" : "0.125rem" }}
        />
      </span>
    </button>
  );
}
