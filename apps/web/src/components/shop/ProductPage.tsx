"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { useState } from "react";

import type { ShopOptionAxis, ShopProduct, ShopStorefront } from "@/api/shop";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { addToCart, cartUnits, memberUnitPriceCents } from "@/lib/shop/cart";
import { choose, initialSelection, isColourAxis, isSoldOut, orderableUnits, selectedVariant, valueStates, type Selection } from "@/lib/shop/variants";

import { CartButton, ErrorNotice, Eyebrow, LoadingLine, Panel, ProductPhoto, ShopHeader } from "./ShopParts";
import { PriceTag, QuantityStepper } from "./shared/ShopBits";
import { shopHref, useBackInStock, useCart, useShopBox, useShopProduct, useStockAlerts, useStorefront } from "./use-shop";

/**
 * A product: photos, the price (and the member's price with their package),
 * every option value visible (Baymard #850) with sold-out ones struck
 * through and «Ειδοποίησέ με» on tap, a quantity, «Στο καλάθι», and where
 * it is picked up. `?post=` is the club post it was opened from (ADR-192
 * attribution); it travels with the cart.
 */
export function ProductPage({ productId }: { productId: string }) {
  const t = useTranslations("Shop");
  const { slug, explicit } = useShopBox();
  const product = useShopProduct(slug, productId);
  const storefront = useStorefront(slug);
  const { cart } = useCart(slug);

  const backHref = shopHref("", slug, explicit);
  const header = (title: string, subtitle?: string | null) => (
    <ShopHeader backHref={backHref} backLabel={t("backToShop")} title={title} subtitle={subtitle} end={<CartButton href={shopHref("/cart", slug, explicit)} units={cartUnits(cart)} />} />
  );

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      {product.data ? (
        <>
          {header(product.data.title, product.data.category)}
          <ProductBody key={product.data.id} product={product.data} storefront={storefront.data ?? null} slug={slug!} explicit={explicit} />
        </>
      ) : product.isError ? (
        <>
          {header(t("title"))}
          <ErrorNotice message={t("productMissing")} />
        </>
      ) : (
        <LoadingLine />
      )}
    </main>
  );
}

function ProductBody({ product, storefront, slug, explicit }: { product: ShopProduct; storefront: ShopStorefront | null; slug: string; explicit: boolean }) {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const searchParams = useSearchParams();
  const postId = searchParams.get("post");
  // A «Προώθηση» post's buy link carries its promotion code (ProductCards.buy_link).
  const postCode = searchParams.get("code");
  const { update } = useCart(slug);
  const axes = product.options.axes;
  const [selection, setSelection] = useState<Selection>(() => initialSelection(axes, product.variants));
  const [quantity, setQuantity] = useState(1);
  const [photo, setPhoto] = useState(0);
  const [added, setAdded] = useState(false);
  const [noticeFor, setNoticeFor] = useState<string | null>(null);
  const backInStock = useBackInStock(slug);
  const alerts = useStockAlerts(slug);

  const variant = selectedVariant(axes, product.variants, selection);
  const max = variant ? orderableUnits(variant, product.per_person_limit) : null;
  const price = variant?.price_cents ?? Math.min(...product.variants.map((item) => item.price_cents));
  const currency = variant?.currency ?? product.variants[0]?.currency ?? storefront?.currency ?? "EUR";
  const percent = storefront?.member_discount_percent ?? null;
  const memberPrice = memberUnitPriceCents(price, product.member_discount_applies, percent);
  const missingAxis = axes.find((axis) => !selection[axis.name]) ?? null;
  const soldOut = variant ? isSoldOut(variant) : false;
  const canAdd = Boolean(variant) && !soldOut && (max === null || max >= quantity);
  const pickupPlaces = (storefront?.pickup_locations ?? []).filter(
    (place) => product.pickup_location_ids.length === 0 || product.pickup_location_ids.includes(place.id),
  );

  function add() {
    if (!variant) return;
    update((current) => {
      const next = addToCart(current, { variantId: variant.id, productId: product.id, quantity }, max);
      return postId && !next.source ? { ...next, source: { kind: "club_post", id: postId, code: postCode } } : next;
    });
    setAdded(true);
  }

  function pick(axis: ShopOptionAxis, value: string) {
    setSelection(choose(axes, product.variants, selection, axis.name, value));
    setQuantity(1);
    setAdded(false);
  }

  const photos = product.photos;
  const shownPhoto = photos[Math.min(photo, Math.max(0, photos.length - 1))];
  const lowLeft = variant && !soldOut && variant.available !== null && variant.available <= 3 ? variant.available : null;

  return (
    <>
      <div className="flex flex-col gap-2">
        <ProductPhoto photo={shownPhoto} title={product.title} />
        {photos.length > 1 ? (
          <div className="grid grid-cols-6 gap-2" role="group" aria-label={t("photos")}>
            {photos.map((item, index) => (
              <button key={item.id} type="button" aria-label={t("photoN", { n: index + 1 })} aria-pressed={index === photo} onClick={() => setPhoto(index)} className="rounded-xl" style={{ outline: index === photo ? "2px solid var(--primary)" : "none", outlineOffset: 2 }}>
                <ProductPhoto photo={item} title={product.title} />
              </button>
            ))}
          </div>
        ) : null}
      </div>

      <div className="flex items-end justify-between gap-3">
        <div className="flex flex-col">
          <span className="text-2xl font-extrabold">
            <PriceTag cents={price} compareAtCents={variant?.compare_at_price_cents} currency={currency} locale={locale} />
          </span>
          {memberPrice < price ? (
            <span className="text-sm" style={{ color: "var(--success)" }}>
              {t("memberPrice", { price: new Intl.NumberFormat(locale, { style: "currency", currency }).format(memberPrice / 100) })}
            </span>
          ) : null}
        </div>
        {product.is_new ? (
          <span className="rounded-full px-2 py-0.5 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", color: "var(--primary-strong)" }}>
            {t("new")}
          </span>
        ) : null}
      </div>

      {axes.length > 0 ? (
        <Panel>
          {axes.map((axis) => (
            <AxisPicker key={axis.name} axis={axis} states={valueStates(axis, product.variants, selection)} value={selection[axis.name] ?? null} onPick={(value) => pick(axis, value)} />
          ))}
          {lowLeft !== null ? (
            <p className="text-sm font-semibold" style={{ color: "var(--warning)" }}>
              {t("lastUnitsOf", { count: lowLeft, variant: variant?.title ?? "" })}
            </p>
          ) : null}
          {soldOut && variant ? (
            <div className="flex flex-wrap items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
              <span>{t("variantSoldOut", { variant: variant.title ?? "" })}</span>
              {alerts.data?.some((alert) => alert.variant_id === variant.id && !alert.notified_at) ? (
                <>
                  <span className="font-semibold" style={{ color: "var(--success)" }}>{t("notifyDone")}</span>
                  <button
                    type="button"
                    className="min-h-9 font-bold underline"
                    style={{ color: "var(--text-soft)" }}
                    disabled={backInStock.isPending}
                    onClick={() => {
                      setNoticeFor(variant.id);
                      backInStock.mutate({ variantId: variant.id, on: false });
                    }}
                  >
                    {t("notifyCancel")}
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  className="min-h-9 font-bold underline"
                  style={{ color: "var(--primary-strong)" }}
                  disabled={backInStock.isPending}
                  onClick={() => {
                    setNoticeFor(variant.id);
                    backInStock.mutate({ variantId: variant.id, on: true });
                  }}
                >
                  {t("notifyMe")}
                </button>
              )}
              {noticeFor === variant.id && backInStock.isError ? <span style={{ color: "var(--danger)" }}>{t("notifyFailed")}</span> : null}
            </div>
          ) : null}
        </Panel>
      ) : null}

      <div className="flex items-center gap-3">
        <QuantityStepper value={quantity} min={1} max={max ?? 99} onChange={(value) => { setQuantity(value); setAdded(false); }} label={t("quantity")} />
        <button
          type="button"
          onClick={add}
          disabled={!canAdd}
          className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="shop-add-to-cart"
        >
          {missingAxis
            ? t("chooseAxis", { axis: missingAxis.name })
            : soldOut
              ? t("soldOut")
              : t("addToCart", { price: new Intl.NumberFormat(locale, { style: "currency", currency }).format((price * quantity) / 100) })}
        </button>
      </div>
      {product.per_person_limit ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("perPersonLimit", { count: product.per_person_limit })}</p>
      ) : null}
      {added ? (
        <Link
          href={shopHref("/cart", slug, explicit)}
          role="status"
          className="flex min-h-11 items-center justify-between gap-2 rounded-2xl px-4 text-sm font-bold"
          style={{ background: "color-mix(in srgb, var(--success) 12%, var(--panel))", color: "var(--text)", border: "1px solid var(--success)" }}
        >
          <span>{t("addedToCart")}</span>
          <span>{t("goToCart")} ›</span>
        </Link>
      ) : null}

      <Panel>
        <Eyebrow>{t("pickup")}</Eyebrow>
        {pickupPlaces.length > 0 ? (
          pickupPlaces.map((place) => (
            <div key={place.id} className="flex flex-col">
              <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{place.name}</span>
              {place.hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{place.hint}</span> : null}
            </div>
          ))
        ) : (
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("pickupAtBox")}</span>
        )}
      </Panel>

      {product.description ? (
        <details className="rounded-3xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <summary className="min-h-9 cursor-pointer text-sm font-bold" style={{ color: "var(--text)" }}>{t("description")}</summary>
          <p className="mt-2 whitespace-pre-wrap text-sm" style={{ color: "var(--text-soft)" }}>{product.description}</p>
        </details>
      ) : null}
    </>
  );
}

/** Every value in a full grid: sizes in equal cells, colours as named chips; sold-out ones struck through. */
function AxisPicker({
  axis,
  states,
  value,
  onPick,
}: {
  axis: ShopOptionAxis;
  states: Record<string, string>;
  value: string | null;
  onPick: (value: string) => void;
}) {
  const t = useTranslations("Shop");
  const colour = isColourAxis(axis);
  const columns = colour ? Math.min(axis.values.length, 3) : Math.min(axis.values.length, 5);
  return (
    <div className="flex flex-col gap-2">
      <Eyebrow>{value ? `${axis.name} · ${value}` : axis.name}</Eyebrow>
      <div role="radiogroup" aria-label={axis.name} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${Math.max(1, columns)}, minmax(0, 1fr))` }}>
        {axis.values.map((option) => {
          const state = states[option];
          const out = state === "sold_out" || state === "missing";
          const selected = value === option;
          return (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={selected}
              aria-label={out ? t("valueSoldOut", { value: option }) : option}
              onClick={() => onPick(option)}
              className="min-h-11 truncate rounded-xl px-2 text-sm font-bold"
              style={{
                background: selected ? "var(--text)" : "var(--panel-raised)",
                color: selected ? "var(--bg)" : out ? "var(--dim)" : "var(--text)",
                border: `1px solid ${selected ? "var(--text)" : "var(--border)"}`,
                textDecoration: out ? "line-through" : "none",
              }}
            >
              {option}
            </button>
          );
        })}
      </div>
    </div>
  );
}
