"use client";

import { useTranslations } from "next-intl";

/** Stock state of a variant (ADR-190 `stock_status`). */
export type ShopStockStatus = "ok" | "low" | "critical" | "out";
import { Pill } from "@/components/staff/staff-ui";
import { formatMoney } from "@/components/inventory/inventory-helpers";

// Generic shop pieces, shared by the console and the member shop: a square
// product photo, the stock meter and badge, a price with its compare-at
// price, and a quantity stepper. Labels come from the `Shop.shared` messages.

/** A square product photo, or a quiet placeholder when there is none. */
export function ProductThumb({ src, alt, size = 48 }: { src?: string | null; alt: string; size?: number }) {
  return (
    <span
      className="inline-flex shrink-0 items-center justify-center overflow-hidden rounded-xl"
      style={{ width: size, height: size, background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--dim)" }}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- media URLs are signed and short-lived
        <img src={src} alt={alt} className="h-full w-full object-cover" loading="lazy" />
      ) : (
        <svg viewBox="0 0 24 24" width={size * 0.45} height={size * 0.45} fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M5 8h14l-1 13H6z" />
          <path d="M9 8V6a3 3 0 0 1 6 0v2" />
        </svg>
      )}
    </span>
  );
}

const STOCK_COLOR: Record<ShopStockStatus, string> = {
  ok: "var(--success)",
  low: "var(--warning)",
  critical: "var(--danger)",
  out: "var(--danger)",
};

/** A thin bar of how much is left; the colour follows the stock state. */
export function StockMeter({ percent, status, label }: { percent: number; status: ShopStockStatus; label: string }) {
  return (
    <span
      role="meter"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={percent}
      className="block h-1.5 w-full overflow-hidden rounded-full"
      style={{ background: "var(--panel-muted)" }}
    >
      <span className="block h-full rounded-full" style={{ width: `${Math.max(percent, status === "out" ? 0 : 4)}%`, background: STOCK_COLOR[status] }} />
    </span>
  );
}

const STOCK_TONE: Record<ShopStockStatus, "success" | "warning" | "danger"> = { ok: "success", low: "warning", critical: "danger", out: "danger" };

export function StockBadge({ status }: { status: ShopStockStatus }) {
  const t = useTranslations("ShopShared");
  return <Pill tone={STOCK_TONE[status]}>{t(`stock.${status}`)}</Pill>;
}

/** The price, with the compare-at price struck through when it is higher. */
export function PriceTag({ cents, compareAtCents, locale, currency = "EUR" }: { cents: number; compareAtCents?: number | null; locale: string; currency?: string }) {
  const t = useTranslations("ShopShared");
  const reduced = typeof compareAtCents === "number" && compareAtCents > cents;
  return (
    <span className="inline-flex flex-wrap items-baseline gap-x-1.5 tabular-nums">
      <b style={{ color: "var(--text)" }}>{formatMoney(cents, locale, currency)}</b>
      {reduced ? (
        <s className="text-xs" style={{ color: "var(--dim)" }} aria-label={t("compareAt", { price: formatMoney(compareAtCents, locale, currency) })}>
          {formatMoney(compareAtCents, locale, currency)}
        </s>
      ) : null}
    </span>
  );
}

/** − n + with a minimum; the label names what is counted. */
export function QuantityStepper({
  value,
  onChange,
  label,
  min = 0,
  max,
}: {
  value: number;
  onChange: (value: number) => void;
  label: string;
  min?: number;
  max?: number;
}) {
  const t = useTranslations("ShopShared");
  const button = "flex h-9 w-9 items-center justify-center rounded-full text-base font-bold disabled:opacity-40";
  const style = { background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" };
  return (
    <span role="group" aria-label={label} className="inline-flex items-center gap-2">
      <button type="button" className={button} style={style} aria-label={t("less")} disabled={value <= min} onClick={() => onChange(value - 1)}>
        −
      </button>
      <b className="min-w-6 text-center tabular-nums" style={{ color: "var(--text)" }} aria-live="polite">
        {value}
      </b>
      <button
        type="button"
        className={button}
        style={style}
        aria-label={t("more")}
        disabled={max !== undefined && value >= max}
        onClick={() => onChange(value + 1)}
      >
        +
      </button>
    </span>
  );
}
