"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { ProductPhoto } from "./ShopParts";

type Snapshot = Record<string, unknown>;

const text = (snapshot: Snapshot, key: string) => (typeof snapshot[key] === "string" && (snapshot[key] as string).trim() ? (snapshot[key] as string).trim() : null);
const integer = (snapshot: Snapshot, key: string) => (typeof snapshot[key] === "number" && Number.isInteger(snapshot[key]) ? (snapshot[key] as number) : null);

/**
 * The deep link of a product card: the product in its box's shop, with the
 * post as the order's source (ADR-192 attribution).
 */
export function productPostHref(snapshot: Snapshot, postId: string | null, fallbackSlug: string | null) {
  const productId = text(snapshot, "product_id") ?? text(snapshot, "id");
  if (!productId) return null;
  const params = new URLSearchParams();
  const slug = text(snapshot, "organization_slug") ?? fallbackSlug;
  if (slug) params.set("box", slug);
  if (postId) params.set("post", postId);
  const qs = params.toString();
  return `/box/shop/product/${encodeURIComponent(productId)}${qs ? `?${qs}` : ""}`;
}

/**
 * A club post's product card (attachment kind `product`, ADR-190
 * Προώθηση): photo, name, price and «Δες το», linking to Box › Κατάστημα,
 * where it is bought (principle 1: a reference, not a second home).
 *
 * TODO(ADR-190): the snapshot keys (`product_id`, `title`, `price_cents`,
 * `currency`, `photo_url`, `variant_summary`, `organization_slug`,
 * `sold_out`) follow the proposal; confirm them when the shop-api branch
 * adds the `product` attachment type.
 */
export function ProductPostCard({ snapshot, postId, organizationSlug }: { snapshot: Snapshot; postId: string | null; organizationSlug: string | null }) {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const title = text(snapshot, "title") ?? t("product");
  const price = integer(snapshot, "price_cents");
  const currency = text(snapshot, "currency") ?? "EUR";
  const summary = text(snapshot, "variant_summary");
  const soldOut = snapshot.sold_out === true;
  const href = productPostHref(snapshot, postId, organizationSlug);
  const details = [price !== null ? formatMinorUnits(locale, price, currency) : null, soldOut ? t("soldOut") : summary].filter(Boolean).join(" · ");

  const body = (
    <>
      <span className="w-14 shrink-0">
        <ProductPhoto photo={{ url: text(snapshot, "photo_url") }} title={title} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("postEyebrow")}</span>
        <span className="truncate font-bold" style={{ color: "var(--text)" }}>{title}</span>
        {details ? <span className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{details}</span> : null}
      </span>
      {href ? (
        <span className="shrink-0 rounded-2xl px-3 py-2 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("seeProduct")}
        </span>
      ) : null}
    </>
  );

  const className = "flex items-center gap-3 rounded-2xl p-3";
  const style = { background: "var(--panel-raised)", border: "1px solid var(--border)" };
  return href ? (
    <Link href={href} className={className} style={style} data-testid="post-product-card">
      {body}
    </Link>
  ) : (
    <div className={className} style={style}>
      {body}
    </div>
  );
}
