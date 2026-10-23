"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import type { ShopOrder } from "@/api/shop";
import { QrCode } from "@/components/check-in/QrCode";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { orderReference, orderTimeline } from "@/lib/shop/catalog";

import { ErrorNotice, LoadingLine, Money, Panel, ProductPhoto, ShopHeader } from "./ShopParts";
import { shopHref, useCancelOrder, useShopBox, useShopOrder } from "./use-shop";

function time(locale: string, value: string | null) {
  if (!value) return null;
  return new Date(value).toLocaleString(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

/**
 * Η παραγγελία μου: the QR and the reference the desk scans, a timeline
 * (placed → ready at the desk → picked up), the lines, how it is paid, and
 * «Ακύρωση» while staff have not handed it over. «Έτοιμη για παραλαβή»
 * reaches the member as a notification that opens this page.
 */
export function OrderPage({ orderId }: { orderId: string }) {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const { slug, explicit } = useShopBox();
  const order = useShopOrder(slug, orderId);
  const back = shopHref("", slug, explicit);
  const data = order.data;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <ShopHeader
        backHref={back}
        backLabel={t("backToShop")}
        title={data ? t("orderTitle", { number: orderReference(data) }) : t("orderTitleLoading")}
        subtitle={data ? time(locale, data.placed_at) : null}
      />
      {data ? <OrderBody order={data} slug={slug!} locale={locale} /> : order.isError ? <ErrorNotice message={t("orderMissing")} /> : <LoadingLine />}
    </main>
  );
}

function OrderBody({ order, slug, locale }: { order: ShopOrder; slug: string; locale: string }) {
  const t = useTranslations("Shop");
  const cancel = useCancelOrder(slug);
  const [confirming, setConfirming] = useState(false);
  const open = order.status === "placed" || order.status === "ready_for_pickup";
  const steps = orderTimeline(order);
  const tone =
    order.status === "ready_for_pickup"
      ? "var(--success)"
      : order.status === "cancelled"
        ? "var(--danger)"
        : order.status === "picked_up"
          ? "var(--dim)"
          : "var(--warning)";

  return (
    <>
      <section className="flex flex-col items-center gap-3 rounded-3xl p-5 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <span className="rounded-full px-3 py-1 text-xs font-bold" style={{ background: `color-mix(in srgb, ${tone} 16%, var(--panel))`, color: tone }} data-testid="shop-order-status">
          {t(`status_${order.status}`)}
        </span>
        {open ? (
          <div className="w-full max-w-[16rem] rounded-3xl p-3" style={{ background: "var(--paper)" }}>
            <QrCode value={order.pickup_code} label={t("orderQr", { number: orderReference(order) })} testId="shop-order-qr" className="aspect-square w-full" />
          </div>
        ) : null}
        <p className="font-mono text-lg font-bold tracking-[0.1em]" style={{ color: "var(--text)" }}>{orderReference(order)}</p>
        {open ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {order.expires_at ? t("showAtDeskUntil", { date: new Date(order.expires_at).toLocaleDateString(locale, { weekday: "short", day: "numeric", month: "numeric" }) }) : t("showAtDesk")}
          </p>
        ) : null}
        {order.status === "cancelled" && order.cancel_reason ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{order.cancel_reason}</p> : null}
      </section>

      <Panel>
        <ol className="flex flex-col gap-3" aria-label={t("timeline")}>
          {steps.map((step) => (
            <li key={step.id} className="grid grid-cols-[1rem_1fr_auto] items-center gap-3" aria-current={step.state === "current" ? "step" : undefined}>
              <span
                aria-hidden="true"
                className="inline-block h-3.5 w-3.5 rounded-full"
                style={{
                  background: step.state === "done" ? "var(--success)" : step.state === "current" ? (step.id === "cancelled" ? "var(--danger)" : "var(--primary)") : "transparent",
                  border: `2px solid ${step.state === "upcoming" ? "var(--border)" : "transparent"}`,
                }}
              />
              <span className="text-sm font-semibold" style={{ color: step.state === "upcoming" ? "var(--dim)" : "var(--text)" }}>
                {t(`step_${step.id}`)}
              </span>
              <span className="text-xs" style={{ color: "var(--dim)" }}>
                {step.at ? time(locale, step.at) : step.id === "picked_up" && order.pickup_location?.hint ? order.pickup_location.hint : ""}
              </span>
            </li>
          ))}
        </ol>
        {order.pickup_location ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("pickupAt", { place: order.pickup_location.name })}</p>
        ) : null}
      </Panel>

      <Panel>
        <ul className="flex flex-col">
          {order.lines.map((line, index) => (
            <li key={line.id} className="grid grid-cols-[3rem_1fr_auto] items-center gap-3 py-2" style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
              <ProductPhoto photo={{ url: line.photo_url }} title={line.product_title} />
              <span className="flex min-w-0 flex-col">
                <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{line.product_title}</span>
                <span className="truncate text-xs" style={{ color: "var(--text-soft)" }}>
                  {[line.variant_title, t("units", { count: line.quantity })].filter(Boolean).join(" · ")}
                </span>
              </span>
              <Money cents={line.total_cents} currency={order.currency} locale={locale} className="text-sm font-bold" />
            </li>
          ))}
        </ul>
        <div className="flex items-center justify-between gap-3 pt-2 text-sm" style={{ borderTop: "1px solid var(--border)", color: "var(--text)" }}>
          <span>{t(order.payment_status === "paid" ? "paidWith" : "payWith", { mode: t(`pay_${order.payment_mode}`) })}</span>
          <Money cents={order.total_cents} currency={order.currency} locale={locale} className="font-extrabold" />
        </div>
      </Panel>

      <Link href="/me/payments" className="min-h-11 self-start text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
        {t("seeInvoice")} ›
      </Link>

      {order.can_cancel ? (
        <button type="button" onClick={() => setConfirming(true)} className="min-h-11 self-start rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--danger)", color: "var(--danger)" }}>
          {t("cancelOrder")}
        </button>
      ) : null}
      {cancel.isError ? <ErrorNotice message={t("cancelFailed")} /> : null}

      {confirming ? (
        <Dialog
          onClose={() => setConfirming(false)}
          title={t("cancelTitle", { number: orderReference(order) })}
          variant="center"
          size="sm"
          dismissible={!cancel.isPending}
          footer={
            <div className="flex w-full gap-2">
              <DialogButton onClick={() => setConfirming(false)}>{t("keepOrder")}</DialogButton>
              <DialogButton
                tone="danger"
                disabled={cancel.isPending}
                onClick={() => cancel.mutate(order.id, { onSettled: () => setConfirming(false) })}
              >
                {t("cancelOrder")}
              </DialogButton>
            </div>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("cancelBody")}</p>
        </Dialog>
      ) : null}
    </>
  );
}
