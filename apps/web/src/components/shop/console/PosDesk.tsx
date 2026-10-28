"use client";

import { useMemo, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { shopIdempotencyKey, type DeskPaymentMethod, type ShopOrder, type ShopProduct, type ShopVariant } from "@/api/shop-admin";
import { useBranchFilter } from "@/components/admin/BranchFilter";
import { Segmented, Toggle } from "@/components/admin/finance/packages/package-ui";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { Field } from "@/components/inventory/inventory-ui";
import { Shell } from "@/components/shop/console/ShopConsole";
import { useDemoGate, useDeskMember, usePosSale, useShopAccess, useShopPaymentMethods, useShopProducts } from "@/components/shop/console/use-shop";
import { ProductThumb, QuantityStepper } from "@/components/shop/shared/ShopBits";
import { useSession } from "@/components/session-provider";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle, StaffPanel, StatusText } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { addToCart, cartTotals, combinationKey, orderLabel, setCartQuantity, type CartLine } from "@/lib/shop/console";
import { BackLink } from "@/components/ui/BackLink";

function availableAt(variant: ShopVariant, locationId: string | null) {
  if (!variant.track_inventory) return null;
  const level = locationId ? variant.stock.find((entry) => entry.location_id === locationId) : null;
  const onHand = level ? level.on_hand : variant.on_hand;
  const reserved = level ? level.reserved : variant.reserved;
  return Math.max(onHand - reserved, 0);
}


/**
 * «Ταμείο» (proposal flow 4): big tiles, a variant quick-pick, the member or
 * a walk-in, cash or card at the terminal (recorded by hand), «Χρέωση». Short
 * stock warns but does not block. The member's unpaid balance shows next to
 * their name.
 */
export function PosDesk() {
  const t = useTranslations("ShopConsole.pos");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const organizationSlug = useOrganizationSlug();
  const access = useShopAccess();
  const gate = useDemoGate();
  const branchFilter = useBranchFilter("shop");
  const branches = branchFilter.locations;
  const [chosenBranch, setChosenBranch] = useState<string | null>(null);
  const locationId = chosenBranch ?? branchFilter.selected[0] ?? branches[0]?.id ?? null;
  const products = useShopProducts("published");
  const methods = useShopPaymentMethods();
  const sale = usePosSale();
  const [search, setSearch] = useState("");
  const [picking, setPicking] = useState<ShopProduct | null>(null);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [walkIn, setWalkIn] = useState(false);
  const [userId, setUserId] = useState("");
  const [userName, setUserName] = useState("");
  const [walkInName, setWalkInName] = useState("");
  const [method, setMethod] = useState<DeskPaymentMethod>("cash");
  const [done, setDone] = useState<ShopOrder | null>(null);
  const idempotency = useRef(shopIdempotencyKey());
  const member = useDeskMember(walkIn || !userId ? null : userId);

  const tiles = useMemo(() => {
    const needle = search.trim().toLocaleLowerCase();
    return (products.data?.products ?? [])
      .filter((product) => product.sell_at_desk && product.status === "published")
      .filter(
        (product) =>
          !needle ||
          product.title.toLocaleLowerCase().includes(needle) ||
          product.variants.some((variant) => variant.sku?.toLocaleLowerCase() === needle || variant.barcode === search.trim()),
      );
  }, [products.data, search]);

  const discountPercent = walkIn ? null : member.summary?.discountPercent ?? null;
  const totals = cartTotals(cart, discountPercent);
  const onlineCard = methods.data?.find((entry) => entry.id === "online_card");

  const add = (product: ShopProduct, variant: ShopVariant) => {
    setDone(null);
    setCart((current) =>
      addToCart(current, {
        variantId: variant.id,
        productTitle: product.title,
        variantTitle: product.options.length > 0 ? combinationKey(variant.option_values, product.options) : null,
        unitPriceCents: variant.price_cents,
        memberDiscount: product.member_discount_applies,
        available: availableAt(variant, locationId),
      }),
    );
    setPicking(null);
  };

  const tap = (product: ShopProduct) => {
    const live = product.variants.filter((variant) => !variant.archived_at);
    if (live.length === 1) add(product, live[0]!);
    else setPicking(product);
  };

  const charge = () =>
    gate(() =>
      sale.mutate(
        {
          location_id: locationId,
          user_id: walkIn ? null : userId || null,
          customer_name: walkIn ? walkInName.trim() || null : userName || null,
          payment_method: method,
          lines: cart.map((line) => ({ variant_id: line.variantId, quantity: line.quantity })),
          idempotency_key: idempotency.current,
        },
        {
          onSuccess: (order) => {
            setDone(order);
            setCart([]);
            setUserId("");
            setUserName("");
            setWalkInName("");
            idempotency.current = shopIdempotencyKey();
          },
        },
      ),
    );

  if (access.isLoading) {
    return (
      <Shell>
        <StatusText tone="muted">{t("loading")}</StatusText>
      </Shell>
    );
  }
  if (!access.sell) {
    return (
      <Shell>
        <StatusText tone="muted">{t("noAccess")}</StatusText>
      </Shell>
    );
  }

  return (
    <Shell>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-col gap-1">
          <BackLink href={adminHref("/admin/shop", organizationSlug)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("back")}</BackLink>
          <h1 className="text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>{t("title")}</h1>
        </div>
        {branches.length >= 2 ? (
          <Field label={t("branch")} className="w-56">
            <Select className={inputClass} style={inputStyle} value={locationId ?? ""} onValueChange={(value) => setChosenBranch(value)}>
              {branches.map((branch) => (
                <option key={branch.id} value={branch.id}>
                  {branch.name}
                </option>
              ))}
            </Select>
          </Field>
        ) : null}
      </div>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <section className="flex flex-col gap-3" aria-label={t("products")}>
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
          ) : tiles.length === 0 ? (
            <StatusText tone="muted">{t("noProducts")}</StatusText>
          ) : (
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" data-testid="pos-tiles">
              {tiles.map((product) => {
                const live = product.variants.filter((variant) => !variant.archived_at);
                const left = live.reduce((sum, variant) => sum + (availableAt(variant, locationId) ?? 0), 0);
                const tracked = live.some((variant) => variant.track_inventory);
                return (
                  <li key={product.id}>
                    <button
                      type="button"
                      onClick={() => tap(product)}
                      aria-pressed={picking?.id === product.id}
                      className="flex min-h-28 w-full flex-col items-start gap-2 rounded-2xl p-3 text-start"
                      style={{ background: "var(--panel)", border: `1px solid ${picking?.id === product.id ? "var(--primary)" : "var(--border)"}` }}
                    >
                      <ProductThumb src={product.media[0]?.thumb_url} alt="" size={44} />
                      <b className="line-clamp-2 text-sm" style={{ color: "var(--text)" }}>{product.title}</b>
                      <span className="text-xs tabular-nums" style={{ color: tracked && left === 0 ? "var(--danger)" : "var(--muted)" }}>
                        {formatMoney(Math.min(...live.map((variant) => variant.price_cents)), locale)}
                        {tracked ? ` · ${t("left", { count: left })}` : ""}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
          {picking ? (
            <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }} role="group" aria-label={t("pickVariant", { product: picking.title })}>
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("pickVariant", { product: picking.title })}</span>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {picking.variants
                  .filter((variant) => !variant.archived_at)
                  .map((variant) => {
                    const left = availableAt(variant, locationId);
                    return (
                      <button
                        key={variant.id}
                        type="button"
                        onClick={() => add(picking, variant)}
                        className="flex flex-col rounded-xl px-3 py-2 text-start text-sm"
                        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: left === 0 ? "var(--dim)" : "var(--text)" }}
                      >
                        <b>{combinationKey(variant.option_values, picking.options)}</b>
                        <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>
                          {formatMoney(variant.price_cents, locale)}
                          {left !== null ? ` · ${t("left", { count: left })}` : ""}
                        </span>
                      </button>
                    );
                  })}
              </div>
            </div>
          ) : null}
        </section>

        <StaffPanel labelledBy="pos-sale" title={t("sale")}>
          <div className="flex flex-col gap-4">
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm" style={{ color: "var(--text)" }}>{t("walkIn")}</span>
              <Toggle checked={walkIn} onChange={setWalkIn} label={t("walkIn")} />
            </label>
            {walkIn ? (
              <Field label={t("walkInName")}>
                <input className={inputClass} style={inputStyle} value={walkInName} onChange={(event) => setWalkInName(event.target.value)} maxLength={80} />
              </Field>
            ) : (
              <>
                <UserSearchField
                  label={t("member")}
                  value={userId}
                  token={token}
                  onChange={(id, user) => {
                    setUserId(id);
                    setUserName(user ? String(user.nickname ?? user.display_name ?? "") : "");
                  }}
                />
                {userId && member.summary ? (
                  <p className="text-sm" style={{ color: member.summary.unpaidCents > 0 ? "var(--warning)" : "var(--muted)" }} data-testid="pos-member-balance">
                    {member.summary.unpaidCents > 0 ? t("unpaid", { amount: formatMoney(member.summary.unpaidCents, locale) }) : t("noUnpaid")}
                    {member.summary.discountPercent ? ` · ${t("packageDiscount", { percent: member.summary.discountPercent })}` : ""}
                  </p>
                ) : null}
              </>
            )}

            {cart.length === 0 ? (
              <StatusText tone="muted">{done ? t("charged", { order: orderLabel(done) }) : t("emptyCart")}</StatusText>
            ) : (
              <ul className="flex flex-col gap-2" data-testid="pos-cart">
                {cart.map((line) => (
                  <li key={line.variantId} className="flex flex-col gap-1">
                    <div className="flex items-center justify-between gap-2">
                      <span className="min-w-0 truncate text-sm" style={{ color: "var(--text)" }}>
                        {[line.productTitle, line.variantTitle].filter(Boolean).join(" · ")}
                      </span>
                      <b className="text-sm tabular-nums" style={{ color: "var(--text)" }}>{formatMoney(line.unitPriceCents * line.quantity, locale)}</b>
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <QuantityStepper value={line.quantity} label={t("quantityOf", { item: line.productTitle })} onChange={(value) => setCart((current) => setCartQuantity(current, line.variantId, value))} />
                      {totals.shortLines.includes(line.variantId) ? (
                        <span className="text-xs font-semibold" style={{ color: "var(--warning)" }}>{t("short", { count: line.available ?? 0 })}</span>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            )}

            {cart.length > 0 ? (
              <dl className="flex flex-col gap-1 text-sm" style={{ borderTop: "1px solid var(--border)", paddingTop: "0.75rem" }}>
                {totals.discountCents > 0 ? (
                  <div className="flex justify-between">
                    <dt style={{ color: "var(--muted)" }}>{t("discount", { percent: discountPercent ?? 0 })}</dt>
                    <dd className="tabular-nums" style={{ color: "var(--text)" }}>−{formatMoney(totals.discountCents, locale)}</dd>
                  </div>
                ) : null}
                <div className="flex justify-between text-base font-bold">
                  <dt style={{ color: "var(--text)" }}>{t("total")}</dt>
                  <dd className="tabular-nums" style={{ color: "var(--text)" }}>{formatMoney(totals.totalCents, locale)}</dd>
                </div>
              </dl>
            ) : null}

            <div className="flex flex-col gap-1.5">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("payment")}</span>
              <Segmented label={t("payment")} value={method} onChange={setMethod} options={(["cash", "card_manual"] as const).map((value) => ({ value, label: t(`methods.${value}`) }))} />
              <span className="text-xs" style={{ color: "var(--dim)" }}>{onlineCard && !onlineCard.available ? t("manualNoteOnlineLater") : t("manualNote")}</span>
            </div>

            <button
              type="button"
              className={`${primaryButtonClass} min-h-12 text-base`}
              style={primaryButtonStyle}
              disabled={cart.length === 0 || sale.isPending || (!walkIn && !userId)}
              onClick={charge}
            >
              {sale.isPending ? t("charging") : t("charge", { amount: formatMoney(totals.totalCents, locale) })}
            </button>
            {!walkIn && !userId && cart.length > 0 ? <span className="text-xs" style={{ color: "var(--dim)" }}>{t("pickMember")}</span> : null}
            {sale.error ? <StatusText tone="error">{localizeError(sale.error, i18n)}</StatusText> : null}
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("receiptNote")}</p>
          </div>
        </StaffPanel>
      </div>
    </Shell>
  );
}
