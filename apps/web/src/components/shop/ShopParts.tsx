"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import type { ReactNode } from "react";

import { ErrorNotice as SharedErrorNotice } from "@/components/ui/ErrorNotice";
import type { ShopPhoto } from "@/api/shop";
import { formatMinorUnits } from "@/lib/finance-accounting";
import type { CardFlag } from "@/lib/shop/variants";

/** A square product photo; a product without one gets a quiet tile with its initial. */
export function ProductPhoto({
  photo,
  title,
  className = "",
  children,
}: {
  photo: ShopPhoto | { url: string | null; alt?: string | null } | null | undefined;
  title: string;
  className?: string;
  children?: ReactNode;
}) {
  return (
    <span
      className={`relative block aspect-square w-full overflow-hidden rounded-2xl ${className}`}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      {photo?.url ? (
        // eslint-disable-next-line @next/next/no-img-element -- media from the box's storage
        <img src={photo.url} alt={photo.alt || title} className="h-full w-full object-cover" loading="lazy" />
      ) : (
        <span aria-hidden="true" className="flex h-full w-full items-center justify-center text-2xl font-extrabold" style={{ color: "var(--dim)" }}>
          {title.trim().charAt(0).toLocaleUpperCase()}
        </span>
      )}
      {children}
    </span>
  );
}

export function Money({ cents, currency, locale, className = "" }: { cents: number; currency: string; locale: string; className?: string }) {
  return <span className={`tabular-nums ${className}`}>{formatMinorUnits(locale, cents, currency)}</span>;
}

export function FlagPill({ flag }: { flag: CardFlag }) {
  const t = useTranslations("Shop");
  if (!flag) return null;
  const tone =
    flag.kind === "sold_out"
      ? { background: "color-mix(in srgb, var(--danger) 16%, var(--panel))", color: "var(--danger)" }
      : flag.kind === "last"
        ? { background: "color-mix(in srgb, var(--warning) 18%, var(--panel))", color: "var(--warning)" }
        : { background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", color: "var(--primary-strong)" };
  const label = flag.kind === "sold_out" ? t("soldOut") : flag.kind === "last" ? t("lastUnits", { count: flag.units }) : t("new");
  return (
    <span className="rounded-full px-2 py-0.5 text-[11px] font-bold" style={tone}>
      {label}
    </span>
  );
}

/** The shop's sub-page top: a way back, the title, and what sits on the end (the cart). */
export function ShopHeader({
  backHref,
  backLabel,
  title,
  subtitle,
  end,
}: {
  backHref: string;
  backLabel: string;
  title: string;
  subtitle?: string | null;
  end?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-1">
      <Link href={backHref} className="inline-flex min-h-9 items-center self-start text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
        ‹ {backLabel}
      </Link>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>
            {title}
          </h1>
          {subtitle ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {subtitle}
            </p>
          ) : null}
        </div>
        {end}
      </div>
    </header>
  );
}

export function CartButton({ href, units }: { href: string; units: number }) {
  const t = useTranslations("Shop");
  return (
    <Link
      href={href}
      aria-label={t("cartWithCount", { count: units })}
      className="inline-flex min-h-11 shrink-0 items-center gap-2 rounded-2xl px-3 text-sm font-bold"
      style={{
        background: units > 0 ? "var(--primary)" : "var(--panel-raised)",
        color: units > 0 ? "var(--primary-contrast)" : "var(--text)",
        border: units > 0 ? "none" : "1px solid var(--border)",
      }}
      data-testid="shop-cart-button"
    >
      <BagIcon />
      {units > 0 ? <span className="tabular-nums">{units}</span> : null}
    </Link>
  );
}

export function BagIcon({ size = 18 }: { size?: number }) {
  return (
    <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 8h12l-1 12H7z" />
      <path d="M9 8V6a3 3 0 0 1 6 0v2" />
    </svg>
  );
}

export function Panel({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section className={`flex flex-col gap-3 rounded-3xl p-4 ${className}`} style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {children}
    </section>
  );
}

export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}

export function LoadingLine() {
  const t = useTranslations("Shop");
  return (
    <p className="py-8 text-center text-sm" style={{ color: "var(--dim)" }}>
      {t("loading")}
    </p>
  );
}

export function ErrorNotice({ message }: { message: string }) {
  return <SharedErrorNotice>{message}</SharedErrorNotice>;
}
