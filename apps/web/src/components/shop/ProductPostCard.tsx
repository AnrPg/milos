"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { ProductPhoto } from "./ShopParts";
import { useShopProduct } from "./use-shop";

type Data = Record<string, unknown>;

const text = (data: Data | null | undefined, key: string) =>
  data && typeof data[key] === "string" && (data[key] as string).trim() ? (data[key] as string).trim() : null;
const integer = (data: Data | null | undefined, key: string) =>
  data && typeof data[key] === "number" && Number.isInteger(data[key]) ? (data[key] as number) : null;
const object = (data: Data | null | undefined, key: string) =>
  data && typeof data[key] === "object" && data[key] !== null ? (data[key] as Data) : null;

/** What the reader can do with the product now (`ProductCards.status`). */
export type ProductCardStatus = "available" | "sold_out" | "members_only" | "unavailable";

/**
 * The deep link of a product card: the product in its box's shop, with the
 * post as the order's source and the post's promotion code (ADR-192
 * attribution). Reads the live card's `buy_link`, else the post snapshot;
 * null while the product cannot be bought.
 */
export function productPostHref(card: Data | null, snapshot: Data, postId: string | null, slug: string | null) {
  const status = (text(card, "status") as ProductCardStatus | null) ?? "available";
  if (status !== "available") return null;
  const link = object(card, "buy_link");
  const productId = text(link, "product_id") ?? text(card, "product_id") ?? text(snapshot, "product_id");
  if (!productId) return null;
  const params = new URLSearchParams();
  if (slug) params.set("box", slug);
  const linkParams = object(link, "params");
  const post = text(linkParams, "source_ref_id") ?? postId;
  if (post) params.set("post", post);
  const code = text(linkParams, "promotion_code");
  if (code) params.set("code", code);
  const qs = params.toString();
  return `/box/shop/product/${encodeURIComponent(productId)}${qs ? `?${qs}` : ""}`;
}

/**
 * A club post's product card (attachment kind `product`, ADR-190
 * «Προώθηση»): name, live price range, the post's code and price with it,
 * and «Δες το», linking to Box › Κατάστημα where it is bought (principle 1:
 * a reference, not a second home). `card` is the live product the API puts
 * on the post (`ProductCards`); the snapshot covers a post read without it.
 * The card carries `media_ids` only, so the photo comes from the member
 * product (cached, and reused by the product page); without it the tile
 * shows the initials.
 */
export function ProductPostCard({ card, snapshot, postId, organizationSlug }: { card: Data | null; snapshot: Data; postId: string | null; organizationSlug: string | null }) {
  const t = useTranslations("Shop");
  const locale = useUiLocale();
  const title = text(card, "title") ?? text(snapshot, "title") ?? t("product");
  const currency = text(card, "currency") ?? text(snapshot, "currency") ?? "EUR";
  const low = integer(card, "price_cents") ?? integer(snapshot, "price_cents");
  const high = integer(card, "max_price_cents") ?? integer(snapshot, "max_price_cents");
  const status = (text(card, "status") as ProductCardStatus | null) ?? "available";
  const promotion = object(card, "promotion");
  const promoCode = text(promotion, "code");
  const promoPrice = integer(card, "promotion_price_cents");
  const money = (cents: number) => formatMinorUnits(locale, cents, currency);
  const price = low === null ? null : high !== null && high !== low ? t("fromPrice", { price: money(low) }) : money(low);
  const state =
    status === "sold_out"
      ? t("soldOut")
      : status === "members_only"
        ? t("postMembersOnly")
        : status === "unavailable"
          ? t("unavailableItem")
          : text(card, "availability") === "low"
            ? t("postFewLeft")
            : null;
  const details = [price, state].filter(Boolean).join(" · ");
  const href = productPostHref(card, snapshot, postId, organizationSlug);
  const productId = text(card, "product_id") ?? text(snapshot, "product_id") ?? "";
  const sellable = status === "available" || status === "sold_out";
  const detail = useShopProduct(sellable ? organizationSlug : null, productId);
  const photo = detail.data?.photos[0] ?? null;

  const body = (
    <>
      <span className="w-14 shrink-0">
        <ProductPhoto photo={photo} title={title} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("postEyebrow")}</span>
        <span className="truncate font-bold" style={{ color: "var(--text)" }}>{title}</span>
        {details ? <span className="truncate text-sm" style={{ color: "var(--text-soft)" }}>{details}</span> : null}
        {promoCode && promoPrice !== null ? (
          <span className="truncate text-sm font-semibold" style={{ color: "var(--success)" }}>{t("postWithCode", { price: money(promoPrice), code: promoCode })}</span>
        ) : null}
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
    <div className={className} style={style} data-testid="post-product-card">
      {body}
    </div>
  );
}
