"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";

import type { ShopOrder } from "@/api/shop";
import { QrCode } from "@/components/check-in/QrCode";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { orderReference, orderTimeline } from "@/lib/shop/catalog";
import { downloadPickupPass, spacedCode } from "@/lib/shop/pickup-pass";

import { ErrorNotice, LoadingLine, Money, Panel, ShopHeader } from "./ShopParts";
import { ProductThumb } from "./shared/ShopBits";
import { shopHref, useCancelOrder, useShopBox, useShopOrder } from "./use-shop";
import { formatClock } from "@/lib/clock";

function time(locale: string, value: string | null) {
  if (!value) return null;
  return formatClock(new Date(value), locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

/**
 * Η παραγγελία μου: the QR and the pickup code the desk scans or types, a
 * timeline (placed → ready at the desk → picked up), the lines, how it is
 * paid, and «Ακύρωση» while staff have not handed it over. «Έτοιμη για
 * παραλαβή» reaches the member as a notification that opens this page.
 * ADR-291 (mockup 2B): just after ordering, a centred window shows the QR and
 * code with what to do at the desk; «Αποθήκευση» keeps both as an image that
 * opens without the app or a connection.
 */
export function OrderPage({ orderId }: { orderId: string }) {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const { slug, explicit } = useShopBox();
  const order = useShopOrder(slug, orderId);
  const back = shopHref("", slug, explicit);
  const data = order.data;
  const router = useRouter();
  const searchParams = useSearchParams();
  const placed = searchParams.get("placed") === "1";

  function closePlaced() {
    const params = new URLSearchParams(searchParams.toString());
    params.delete("placed");
    const query = params.toString();
    router.replace(`${window.location.pathname}${query ? `?${query}` : ""}`, { scroll: false });
  }

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <ShopHeader
        backHref={back}
        backLabel={t("backToShop")}
        title={data ? t("orderTitle", { number: orderReference(data) }) : t("orderTitleLoading")}
        subtitle={data ? time(locale, data.placed_at) : null}
      />
      {data ? <OrderBody order={data} slug={slug!} locale={locale} /> : order.isError ? <ErrorNotice message={t("orderMissing")} /> : <LoadingLine />}
      {data && placed && data.payment_mode !== "online" ? <PlacedDialog order={data} locale={locale} onClose={closePlaced} /> : null}
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
        {open ? (
          <p className="flex flex-col items-center" data-testid="shop-order-code">
            <span className="text-xs font-bold" style={{ color: "var(--dim)" }}>{t("pickupCode")}</span>
            <span className="font-mono text-2xl font-extrabold tracking-[0.18em]" style={{ color: "var(--text)" }}>{spacedCode(order.pickup_code)}</span>
          </p>
        ) : null}
        <p className="font-mono text-lg font-bold tracking-[0.1em]" style={{ color: "var(--text)" }}>{orderReference(order)}</p>
        {open ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {order.expires_at ? t("showAtDeskUntil", { date: new Date(order.expires_at).toLocaleDateString(locale, { weekday: "short", day: "numeric", month: "numeric" }) }) : t("showAtDesk")}
          </p>
        ) : null}
        {open ? <SavePassButton order={order} locale={locale} /> : null}
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
              <ProductThumb src={line.photo_url} alt={line.product_title} size={48} />
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
      {cancel.isError && !confirming ? <ErrorNotice message={t("cancelFailed")} /> : null}

      {confirming ? (
        <Dialog
          onClose={() => setConfirming(false)}
          // ADR-214: a failed cancel keeps the dialog open and says so inside it.
          error={cancel.isError ? t("cancelFailed") : undefined}
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
                onClick={() => cancel.mutate(order.id, { onSuccess: () => setConfirming(false) })}
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

/** «Αποθήκευση»: the QR and the code as one image for the photos. */
function SavePassButton({ order, locale, testId = "shop-order-save" }: { order: ShopOrder; locale: string; testId?: string }) {
  const t = useTranslations("Shop");
  const [state, setState] = useState<"idle" | "saving" | "saved" | "failed">("idle");

  async function save() {
    setState("saving");
    try {
      await downloadPickupPass({
        code: order.pickup_code,
        reference: orderReference(order),
        box: null,
        place: order.pickup_location?.name ?? null,
        total: new Intl.NumberFormat(locale, { style: "currency", currency: order.currency }).format(order.total_cents / 100),
        labels: { code: t("pickupCode"), showAtDesk: t("showAtDesk") },
      });
      setState("saved");
    } catch {
      setState("failed");
    }
  }

  return (
    <span className="flex flex-col items-center gap-1">
      <button
        type="button"
        onClick={save}
        disabled={state === "saving"}
        className="min-h-11 rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        data-testid={testId}
      >
        {t("savePass")}
      </button>
      {state === "saved" ? <span className="text-xs" style={{ color: "var(--success)" }}>{t("savePassDone")}</span> : null}
      {state === "failed" ? <span className="text-xs" style={{ color: "var(--danger)" }}>{t("savePassFailed")}</span> : null}
    </span>
  );
}

/** Just after ordering: the QR, the code and what to do at the desk, in the middle of the screen. */
function PlacedDialog({ order, locale, onClose }: { order: ShopOrder; locale: string; onClose: () => void }) {
  const t = useTranslations("Shop");
  const total = new Intl.NumberFormat(locale, { style: "currency", currency: order.currency }).format(order.total_cents / 100);
  const paid = order.payment_status === "paid";
  return (
    <Dialog onClose={onClose} title={t("placedTitle")} variant="center" size="sm" testId="shop-placed">
      <div className="flex min-w-0 flex-col items-center gap-3 text-center">
        <div className="w-full max-w-[13rem] rounded-3xl p-3" style={{ background: "var(--paper)" }}>
          <QrCode value={order.pickup_code} label={t("orderQr", { number: orderReference(order) })} testId="shop-placed-qr" className="aspect-square w-full" />
        </div>
        <p className="flex flex-col items-center">
          <span className="text-xs font-bold" style={{ color: "var(--dim)" }}>{t("pickupCode")}</span>
          <span className="font-mono text-2xl font-extrabold tracking-[0.18em]" style={{ color: "var(--text)" }} data-testid="shop-placed-code">
            {spacedCode(order.pickup_code)}
          </span>
        </p>
        <ol className="flex w-full list-decimal flex-col gap-1 ps-5 text-start text-sm" style={{ color: "var(--text)" }}>
          <li>{t("placedStepShow")}</li>
          {paid ? null : <li>{t("placedStepPay", { total })}</li>}
          <li>{t("placedStepTake")}</li>
        </ol>
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("placedNote")}</p>
        <SavePassButton order={order} locale={locale} testId="shop-placed-save" />
        <button
          type="button"
          onClick={onClose}
          className="min-h-11 w-full rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="shop-placed-ok"
        >
          {t("gotIt")}
        </button>
      </div>
    </Dialog>
  );
}
