"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";

import { ApiError } from "@/api/client";
import type { ShopPaymentMode, ShopProductSummary, ShopVariant } from "@/api/shop";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { EMPTY_CART, cartItems, cartTotals, removeLine, setLineQuantity } from "@/lib/shop/cart";
import { orderableUnits } from "@/lib/shop/variants";

import { ErrorNotice, Eyebrow, LoadingLine, Money, Panel, ShopHeader } from "./ShopParts";
import { ProductThumb, QuantityStepper } from "./shared/ShopBits";
import { shopHref, useCart, useCartPreview, usePlaceOrder, usePricedCatalog, useShopBox, useShopProducts, useStorefront } from "./use-shop";

const ORDER_ERRORS: Record<string, string> = {
  per_person_limit_exceeded: "errorLimit",
  product_not_available: "errorUnavailable",
  variant_not_found: "errorUnavailable",
  insufficient_stock: "errorStock",
  promotion_code_invalid: "errorCode",
  promotion_code_expired: "errorCode",
  promotion_code_exhausted: "errorCode",
  promotion_code_changed: "errorCode",
  promotion_code_not_applicable: "errorCode",
};

const isCodeError = (error: unknown) => error instanceof ApiError && String(error.payload.code ?? "").startsWith("promotion_code_");

function errorKey(error: unknown) {
  const code = error instanceof ApiError ? error.payload.code : null;
  return (code && ORDER_ERRORS[code]) || "errorOrder";
}

function newKey() {
  return typeof crypto !== "undefined" && typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}

/**
 * Cart and checkout on one screen with no typed fields (Baymard): the lines,
 * the pickup point (a choice only when there are several), how to pay (at
 * pickup, on the account when the owner allows it, and online card shown
 * greyed out until `online_payment.available`), a code behind «Έχεις
 * κωδικό;», the totals in cents, and «Παραγγελία». The invoice then shows in
 * Εγώ › Πληρωμές › Συναλλαγές.
 */
export function CartPage() {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const router = useRouter();
  const { slug, explicit, isLoading } = useShopBox();
  const storefront = useStorefront(slug);
  const products = useShopProducts(slug);
  const { cart, update } = useCart(slug);
  const catalog = usePricedCatalog(products.data);
  const shop = storefront.data;
  const totals = cartTotals(cart, catalog, shop?.member_discount_percent ?? null);
  const byVariant = useMemo(() => {
    const map = new Map<string, { product: ShopProductSummary; variant: ShopVariant }>();
    for (const product of products.data ?? []) for (const variant of product.variants) map.set(variant.id, { product, variant });
    return map;
  }, [products.data]);

  const orderable = cart.lines.filter((line) => !totals.missing.includes(line.variantId));
  const [pickupId, setPickupId] = useState<string | null>(null);
  // A code from a «Προώθηση» post starts typed in; «Έχεις κωδικό;» can set another.
  // `undefined` until the member types or removes one; the stored cart loads after hydration.
  const [typedPromotion, setPromotion] = useState<string | null | undefined>(undefined);
  const promotion = typedPromotion === undefined ? (cart.source?.code ?? null) : typedPromotion;
  // The server prices the basket (with the code) and says where it can be picked up and how it can be paid.
  const preview = useCartPreview(slug, cartItems({ ...cart, lines: orderable }), pickupId, promotion);
  const codeRejected = Boolean(promotion) && preview.isError && isCodeError(preview.error);
  const quote = codeRejected ? null : (preview.data ?? null);
  const allowed = quote?.pickup_location_ids ?? [];
  const places = (shop?.pickup_locations ?? []).filter((item) => allowed.length === 0 || allowed.includes(item.id));
  const pickup = places.find((item) => item.id === pickupId) ?? places[0] ?? null;
  const serverModes = quote?.payment_modes ?? ["at_pickup"];
  const onlineAvailable = quote?.online_payment.available ?? false;
  const modes: { mode: ShopPaymentMode; available: boolean }[] = [
    { mode: "at_pickup", available: serverModes.includes("at_pickup") },
    ...(serverModes.includes("on_account") ? [{ mode: "on_account" as const, available: true }] : []),
    // Owner's call: online card payment is visible but blocked until the provider ships.
    { mode: "online", available: onlineAvailable },
  ];
  const [mode, setMode] = useState<ShopPaymentMode>("at_pickup");
  const [openState, setCodeOpen] = useState(false);
  const codeOpen = openState || Boolean(promotion);
  const [typedCode, setCode] = useState<string | null>(null);
  const code = typedCode ?? promotion ?? "";
  const [idempotencyKey] = useState(newKey);
  const place = usePlaceOrder(slug);
  const currency = quote?.currency ?? totals.currency ?? shop?.currency ?? "EUR";
  const back = shopHref("", slug, explicit);

  function applyCode() {
    const value = code.trim();
    setPromotion(value || null);
  }

  function placeOrder() {
    if (!slug || totals.lines.length === 0) return;
    place.mutate(
      {
        lines: cartItems({ ...cart, lines: orderable }),
        pickup_location_id: pickup?.id ?? null,
        payment_mode: mode,
        promotion_code: codeRejected ? null : promotion,
        source: cart.source ? cart.source.kind : "direct",
        source_ref_id: cart.source?.id ?? null,
        idempotency_key: idempotencyKey,
      },
      {
        onSuccess: (order) => {
          update(() => EMPTY_CART);
          router.replace(shopHref(`/orders/${encodeURIComponent(order.id)}`, slug, explicit));
        },
      },
    );
  }

  const header = <ShopHeader backHref={back} backLabel={t("backToShop")} title={t("cartTitle")} subtitle={cart.lines.length > 0 ? t("cartCount", { count: totals.lines.length }) : null} />;

  if (isLoading || products.isLoading || storefront.isLoading) {
    return (
      <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
        {header}
        <LoadingLine />
      </main>
    );
  }

  if (cart.lines.length === 0) {
    return (
      <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
        {header}
        <div className="flex flex-col items-center gap-3 rounded-3xl px-5 py-8 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("cartEmpty")}</p>
          <Link href={back} className="min-h-11 rounded-2xl px-4 py-3 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("browseShop")}
          </Link>
        </div>
      </main>
    );
  }

  const discountCents = quote ? quote.discount_cents : totals.discountCents;
  const totalCents = quote ? quote.total_cents : totals.totalCents;
  const subtotalCents = quote ? quote.subtotal_cents : totals.subtotalCents;
  // The package discount never stacks with a code: the row names whichever the server applied.
  const percent = quote ? quote.member_discount_percent : (shop?.member_discount_percent ?? null);
  const discountLabel = quote?.promotion_code
    ? t("codeDiscount", { code: quote.promotion_code })
    : percent
      ? t("packageDiscount", { percent })
      : t("packageDiscountPlain");

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      {header}

      <Panel>
        <ul className="flex flex-col">
          {cart.lines.map((line, index) => {
            const entry = byVariant.get(line.variantId);
            const priced = totals.lines.find((item) => item.variantId === line.variantId);
            const max = entry ? orderableUnits(entry.variant, entry.product.per_person_limit) : null;
            return (
              <li key={line.variantId} className="grid grid-cols-[3.5rem_1fr_auto] items-center gap-3 py-3" style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
                <ProductThumb src={entry?.product.photos[0]?.url} alt={entry?.product.title ?? ""} size={56} />
                <div className="flex min-w-0 flex-col gap-1">
                  <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{entry?.product.title ?? t("unavailableItem")}</span>
                  {entry?.variant.title ? <span className="truncate text-xs" style={{ color: "var(--text-soft)" }}>{entry.variant.title}</span> : null}
                  {entry && priced ? (
                    <div className="flex items-center gap-2">
                      <QuantityStepper
                        min={1}
                        value={line.quantity}
                        max={max ?? 99}
                        label={t("quantityOf", { item: entry.product.title })}
                        onChange={(value) => update((current) => setLineQuantity(current, line.variantId, value, max))}
                      />
                      <button type="button" className="min-h-11 px-2 text-xs font-bold" style={{ color: "var(--danger)" }} onClick={() => update((current) => removeLine(current, line.variantId))}>
                        {t("remove")}
                      </button>
                    </div>
                  ) : (
                    <button type="button" className="min-h-9 self-start text-xs font-bold" style={{ color: "var(--danger)" }} onClick={() => update((current) => removeLine(current, line.variantId))}>
                      {t("remove")}
                    </button>
                  )}
                </div>
                {priced ? <Money cents={priced.grossCents} currency={currency} locale={locale} className="text-sm font-bold" /> : null}
              </li>
            );
          })}
        </ul>
      </Panel>

      <Panel>
        <Eyebrow>{t("pickup")}</Eyebrow>
        {places.length > 1 ? (
          <div role="radiogroup" aria-label={t("pickup")} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {places.map((item) => (
              <OptionCard key={item.id} selected={pickup?.id === item.id} onSelect={() => setPickupId(item.id)} title={item.name} hint={item.hint} />
            ))}
          </div>
        ) : (
          <div className="flex flex-col">
            <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{pickup?.name ?? t("pickupAtBox")}</span>
            {pickup?.hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{pickup.hint}</span> : null}
          </div>
        )}
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("pickupNotice")}</span>
      </Panel>

      <Panel>
        <Eyebrow>{t("payment")}</Eyebrow>
        <div role="radiogroup" aria-label={t("payment")} className="grid grid-cols-1 gap-2">
          {modes.map(({ mode: option, available }) => (
            <OptionCard
              key={option}
              selected={mode === option}
              disabled={!available}
              onSelect={() => setMode(option)}
              title={t(`pay_${option}`)}
              hint={option === "online" && !available ? t("pay_online_blocked") : t(`pay_${option}_hint`)}
              testId={`shop-pay-${option}`}
            />
          ))}
        </div>
      </Panel>

      {codeOpen ? (
        <Panel>
          <label className="flex flex-col gap-2">
            <Eyebrow>{t("codeLabel")}</Eyebrow>
            <span className="flex gap-2">
              <input
                value={code}
                onChange={(event) => setCode(event.target.value.toLocaleUpperCase())}
                autoCapitalize="characters"
                autoComplete="off"
                className="min-h-11 min-w-0 flex-1 rounded-2xl px-3 font-mono text-sm outline-none"
                style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
              />
              <button type="button" onClick={applyCode} disabled={!code.trim()} className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50" style={{ background: "var(--text)", color: "var(--bg)" }}>
                {t("apply")}
              </button>
            </span>
          </label>
          {codeRejected ? (
            <div className="flex items-center justify-between gap-2">
              <ErrorNotice message={t(errorKey(preview.error))} />
              <button type="button" onClick={() => { setPromotion(null); setCode(""); }} className="min-h-11 px-2 text-xs font-bold" style={{ color: "var(--danger)" }}>
                {t("remove")}
              </button>
            </div>
          ) : quote?.promotion_code ? (
            <span className="text-sm font-semibold" style={{ color: "var(--success)" }}>{t("codeApplied", { code: quote.promotion_code })}</span>
          ) : null}
        </Panel>
      ) : (
        <button type="button" onClick={() => setCodeOpen(true)} className="min-h-11 self-start text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
          {t("haveCode")}
        </button>
      )}

      <Panel>
        <dl className="flex flex-col gap-1 text-sm">
          <Row label={t("subtotal")} value={<Money cents={subtotalCents} currency={currency} locale={locale} />} />
          {discountCents > 0 ? (
            <Row
              label={discountLabel}
              value={<span style={{ color: "var(--success)" }}>−<Money cents={discountCents} currency={currency} locale={locale} /></span>}
            />
          ) : null}
          <Row strong label={t("total")} value={<Money cents={totalCents} currency={currency} locale={locale} />} />
        </dl>
      </Panel>

      {place.isError ? <ErrorNotice message={t(errorKey(place.error))} /> : null}
      <button
        type="button"
        onClick={placeOrder}
        disabled={place.isPending || totals.lines.length === 0 || (mode === "online" && !onlineAvailable)}
        className="min-h-12 rounded-2xl px-4 text-base font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="shop-place-order"
      >
        {place.isPending ? t("placing") : t(`place_${mode}`, { total: new Intl.NumberFormat(locale, { style: "currency", currency }).format(totalCents / 100) })}
      </button>
      <p className="text-center text-xs" style={{ color: "var(--dim)" }}>{t("invoiceNote")}</p>
    </main>
  );
}

function Row({ label, value, strong }: { label: string; value: React.ReactNode; strong?: boolean }) {
  return (
    <div className={`flex items-center justify-between gap-3 ${strong ? "pt-2 text-base font-extrabold" : ""}`} style={{ borderTop: strong ? "1px solid var(--border)" : "none", color: "var(--text)" }}>
      <dt>{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}

function OptionCard({
  selected,
  disabled,
  onSelect,
  title,
  hint,
  testId,
}: {
  selected: boolean;
  disabled?: boolean;
  onSelect: () => void;
  title: string;
  hint?: string | null;
  testId?: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      aria-disabled={disabled || undefined}
      disabled={disabled}
      onClick={onSelect}
      data-testid={testId}
      className="flex min-h-12 w-full items-start gap-3 rounded-2xl px-4 py-3 text-start disabled:cursor-not-allowed disabled:opacity-50"
      style={{
        background: selected && !disabled ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel-raised)",
        border: `1px solid ${selected && !disabled ? "var(--primary)" : "var(--border)"}`,
        color: "var(--text)",
      }}
    >
      <span
        aria-hidden="true"
        className="mt-0.5 inline-block h-4 w-4 shrink-0 rounded-full"
        style={{ border: `2px solid ${selected && !disabled ? "var(--primary)" : "var(--dim)"}`, background: selected && !disabled ? "var(--primary)" : "transparent" }}
      />
      <span className="flex min-w-0 flex-col">
        <span className="text-sm font-bold">{title}</span>
        {hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
      </span>
    </button>
  );
}
