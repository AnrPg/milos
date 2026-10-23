"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { useTranslations } from "next-intl";

import type { DeskPaymentMethod, ShopOrder, ShopOrderStatus } from "@/api/shop";
import type { BranchFilterState } from "@/components/admin/BranchFilter";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { Segmented, Toggle } from "@/components/admin/finance/packages/package-ui";
import { formatDateTime } from "@/components/client/format";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { formatMoney } from "@/components/inventory/inventory-helpers";
import { Field } from "@/components/inventory/inventory-ui";
import { branchName } from "@/components/shop/console/ShopConsole";
import { useDemoGate, useOrderAction, useShopAccess, useShopOrder, useShopOrders } from "@/components/shop/console/use-shop";
import { ProductThumb, QuantityStepper } from "@/components/shop/shared/ShopBits";
import { dangerButtonStyle, inputClass, inputStyle, Pill, primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { orderActions, orderLabel, pickupNeedsPayment, refundableLines } from "@/lib/shop/console";

const STATUSES: ShopOrderStatus[] = ["placed", "ready_for_pickup", "picked_up", "cancelled"];
const STATUS_TONE: Record<ShopOrderStatus, "primary" | "spark" | "success" | "neutral"> = {
  placed: "primary",
  ready_for_pickup: "spark",
  picked_up: "success",
  cancelled: "neutral",
};

export function OrdersTab({ locationIds, branchFilter }: { locationIds?: string; branchFilter: BranchFilterState }) {
  const t = useTranslations("ShopConsole.orders");
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const [status, setStatus] = useState<ShopOrderStatus>("placed");
  const orders = useShopOrders(status, locationIds);
  const counts = orders.data?.counts;
  const openId = searchParams.get("order");

  const openOrder = (id: string | null) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("tab", "orders");
    if (id) params.set("order", id);
    else params.delete("order");
    router.replace(`?${params.toString()}`, { scroll: false });
  };

  return (
    <section className="flex flex-col gap-4" aria-label={t("title")}>
      <SegmentPicker
        ariaLabel={t("filter")}
        semantics="radiogroup"
        value={status}
        onChange={setStatus}
        options={STATUSES.map((value) => ({
          value,
          label: t(`status.${value}`),
          count: counts && (value === "placed" || value === "ready_for_pickup") ? counts[value] : null,
        }))}
      />
      {orders.isLoading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : orders.error ? (
        <StatusText tone="error">{localizeError(orders.error, i18n)}</StatusText>
      ) : (orders.data?.orders ?? []).length === 0 ? (
        <StatusText tone="muted">{t(`none.${status}`)}</StatusText>
      ) : (
        <ul className="flex flex-col gap-2" data-testid="shop-orders">
          {(orders.data?.orders ?? []).map((order) => (
            <OrderRow key={order.id} order={order} branch={branchFilter.visible ? branchName(branchFilter, order.pickup_location_id) : null} onOpen={() => openOrder(order.id)} />
          ))}
        </ul>
      )}
      {status === "placed" ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("reserveNote")}</p> : null}
      {openId ? <OrderPanel orderId={openId} onClose={() => openOrder(null)} /> : null}
    </section>
  );
}

function customerOf(order: Pick<ShopOrder, "customer_name" | "user_id">, walkIn: string) {
  return order.customer_name || walkIn;
}

function OrderRow({ order, branch, onOpen }: { order: ShopOrder; branch: string | null; onOpen: () => void }) {
  const t = useTranslations("ShopConsole.orders");
  const locale = useUiLocale();
  const summary = order.lines.map((line) => [line.product_title, line.variant_title].filter(Boolean).join(" ") + (line.quantity > 1 ? ` ×${line.quantity}` : "")).join(", ");
  return (
    <li>
      <button
        type="button"
        onClick={onOpen}
        className="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-2xl p-3 text-start"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <span className="flex min-w-0 flex-col">
          <b className="truncate text-sm" style={{ color: "var(--text)" }}>
            {orderLabel(order)} · {customerOf(order, t("walkIn"))}
          </b>
          <span className="truncate text-xs" style={{ color: "var(--muted)" }}>{summary}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {[formatDateTime(order.placed_at, locale), t(`channel.${order.channel}`), branch].filter(Boolean).join(" · ")}
          </span>
        </span>
        <span className="flex flex-col items-end gap-1">
          <b className="text-sm tabular-nums" style={{ color: "var(--text)" }}>{formatMoney(order.total_cents, locale, order.currency)}</b>
          <span className="text-xs" style={{ color: "var(--muted)" }}>{t(`payment.${order.payment_status}`)}</span>
        </span>
      </button>
    </li>
  );
}

type Step = null | "pickup" | "cancel" | "refund";

/** The order detail drawer: lines, invoice, timeline and the next step. */
export function OrderPanel({ orderId, onClose }: { orderId: string; onClose: () => void }) {
  const t = useTranslations("ShopConsole.orders");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const access = useShopAccess();
  const gate = useDemoGate();
  const order = useShopOrder(orderId);
  const act = useOrderAction(orderId);
  const [step, setStep] = useState<Step>(null);
  const [method, setMethod] = useState<DeskPaymentMethod>("cash");
  const [reason, setReason] = useState("");
  const [refund, setRefund] = useState<Record<string, number>>({});
  const [restock, setRestock] = useState(true);
  const data = order.data;

  const done = () => setStep(null);
  const actions = data ? orderActions(data) : [];

  return (
    <SidePanel title={data ? orderLabel(data) : t("loading")} subtitle={data ? t(`status.${data.status}`) : undefined} onClose={onClose}>
      {order.isLoading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : order.error || !data ? (
        <StatusText tone="error">{localizeError(order.error, i18n)}</StatusText>
      ) : (
        <div className="flex flex-col gap-5" data-testid="shop-order-panel">
          <div className="flex flex-wrap items-center gap-2">
            <Pill tone={STATUS_TONE[data.status]}>{t(`status.${data.status}`)}</Pill>
            <span className="text-sm" style={{ color: "var(--text)" }}>{customerOf(data, t("walkIn"))}</span>
          </div>

          <ul className="flex flex-col gap-2">
            {data.lines.map((line) => (
              <li key={line.id} className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3">
                <ProductThumb src={line.thumb_url} alt={line.product_title} size={40} />
                <span className="flex min-w-0 flex-col">
                  <b className="truncate text-sm" style={{ color: "var(--text)" }}>{[line.product_title, line.variant_title].filter(Boolean).join(" · ")}</b>
                  <span className="text-xs" style={{ color: "var(--muted)" }}>
                    {t("lineQty", { count: line.quantity, price: formatMoney(line.unit_price_cents, locale, data.currency) })}
                    {line.discount_cents > 0 ? ` · −${formatMoney(line.discount_cents, locale, data.currency)}` : ""}
                    {line.refunded_quantity > 0 ? ` · ${t("lineRefunded", { count: line.refunded_quantity })}` : ""}
                  </span>
                </span>
                <span className="text-sm tabular-nums" style={{ color: "var(--text)" }}>{formatMoney(line.total_cents, locale, data.currency)}</span>
              </li>
            ))}
          </ul>

          <dl className="flex flex-col gap-1 text-sm">
            {data.discount_cents > 0 ? <Row label={t("discount")} value={`−${formatMoney(data.discount_cents, locale, data.currency)}`} /> : null}
            <Row label={data.invoice_number ? t("totalWithInvoice", { invoice: data.invoice_number }) : t("total")} value={formatMoney(data.total_cents, locale, data.currency)} strong />
            <Row label={t("paid")} value={formatMoney(data.paid_cents, locale, data.currency)} />
            {data.refunded_cents > 0 ? <Row label={t("refunded")} value={formatMoney(data.refunded_cents, locale, data.currency)} /> : null}
            <Row label={t("paymentMode")} value={t(`mode.${data.payment_mode}`)} />
            {data.promotion_code ? <Row label={t("code")} value={data.promotion_code} /> : null}
          </dl>

          <ol className="flex flex-col gap-1 text-xs" style={{ color: "var(--muted)" }} aria-label={t("timeline")}>
            <li>{t("timelinePlaced", { when: formatDateTime(data.placed_at, locale), channel: t(`channel.${data.channel}`) })}</li>
            {data.ready_at ? <li>{t("timelineReady", { when: formatDateTime(data.ready_at, locale) })}</li> : null}
            {data.picked_up_at ? <li>{t("timelinePickedUp", { when: formatDateTime(data.picked_up_at, locale) })}</li> : null}
            {data.cancelled_at ? <li>{t("timelineCancelled", { when: formatDateTime(data.cancelled_at, locale) })}</li> : null}
            {data.status !== "picked_up" && data.status !== "cancelled" && data.expires_at ? <li>{t("timelineExpires", { when: formatDateTime(data.expires_at, locale) })}</li> : null}
          </ol>

          {!access.sell ? null : step === "pickup" ? (
            <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
              {pickupNeedsPayment(data) ? (
                <>
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {t("collect", { amount: formatMoney(data.total_cents - data.paid_cents, locale, data.currency) })}
                  </span>
                  <Segmented label={t("method")} value={method} onChange={setMethod} options={(["cash", "card_manual"] as const).map((value) => ({ value, label: t(`mode.${value}`) }))} />
                  <span className="text-xs" style={{ color: "var(--dim)" }}>{t("collectHint")}</span>
                </>
              ) : null}
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  className={primaryButtonClass}
                  style={primaryButtonStyle}
                  disabled={act.isPending}
                  onClick={() => gate(() => act.mutate({ action: "pickup", payment_method: pickupNeedsPayment(data) ? method : undefined }, { onSuccess: done }))}
                >
                  {t("confirmPickup")}
                </button>
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={done}>{t("back")}</button>
              </div>
            </div>
          ) : step === "cancel" ? (
            <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
              <Field label={t("cancelReason")}>
                <input className={inputClass} style={inputStyle} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={200} />
              </Field>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("cancelHint")}</span>
              <div className="flex flex-wrap gap-2">
                <button type="button" className={primaryButtonClass} style={dangerButtonStyle} disabled={act.isPending} onClick={() => act.mutate({ action: "cancel", reason: reason.trim() || null }, { onSuccess: done })}>
                  {t("confirmCancel")}
                </button>
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={done}>{t("back")}</button>
              </div>
            </div>
          ) : step === "refund" ? (
            <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("refundWhat")}</span>
              {refundableLines(data).map(({ line, remaining }) => (
                <div key={line.id} className="flex items-center justify-between gap-2">
                  <span className="min-w-0 truncate text-sm" style={{ color: "var(--text)" }}>{[line.product_title, line.variant_title].filter(Boolean).join(" · ")}</span>
                  <QuantityStepper value={refund[line.id] ?? 0} max={remaining} label={t("refundQty", { item: line.product_title })} onChange={(value) => setRefund((current) => ({ ...current, [line.id]: value }))} />
                </div>
              ))}
              <label className="flex items-center justify-between gap-3">
                <span className="text-sm" style={{ color: "var(--text)" }}>{t("restock")}</span>
                <Toggle checked={restock} onChange={setRestock} label={t("restock")} />
              </label>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("refundHint")}</span>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  className={primaryButtonClass}
                  style={dangerButtonStyle}
                  disabled={act.isPending || Object.values(refund).every((quantity) => !quantity)}
                  onClick={() =>
                    act.mutate(
                      { action: "refund", restock, lines: Object.entries(refund).filter(([, quantity]) => quantity > 0).map(([line_id, quantity]) => ({ line_id, quantity })) },
                      { onSuccess: done },
                    )
                  }
                >
                  {t("confirmRefund")}
                </button>
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={done}>{t("back")}</button>
              </div>
            </div>
          ) : actions.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {actions.includes("ready") ? (
                <button type="button" className={primaryButtonClass} style={primaryButtonStyle} disabled={act.isPending} onClick={() => gate(() => act.mutate({ action: "ready" }))}>
                  {t("markReady")}
                </button>
              ) : null}
              {actions.includes("pickup") ? (
                <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={() => setStep("pickup")}>
                  {t("markPickedUp")}
                </button>
              ) : null}
              {actions.includes("cancel") ? (
                <button type="button" className={secondaryButtonClass} style={dangerButtonStyle} onClick={() => setStep("cancel")}>
                  {t("cancel")}
                </button>
              ) : null}
              {actions.includes("refund") && access.refund ? (
                <button type="button" className={secondaryButtonClass} style={dangerButtonStyle} onClick={() => setStep("refund")}>
                  {t("refund")}
                </button>
              ) : null}
            </div>
          ) : null}
          {actions.includes("ready") && step === null ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("readyHint")}</p> : null}
          {act.error ? <StatusText tone="error">{localizeError(act.error, i18n)}</StatusText> : null}
        </div>
      )}
    </SidePanel>
  );
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt style={{ color: "var(--muted)" }}>{label}</dt>
      <dd className="tabular-nums" style={{ color: "var(--text)", fontWeight: strong ? 700 : 400 }}>{value}</dd>
    </div>
  );
}
