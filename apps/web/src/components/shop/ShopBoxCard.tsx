"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";
import { HubCard } from "@/components/member-app/HubParts";
import { orderReference, sortOpenOrders } from "@/lib/shop/catalog";

import { ProductPhoto } from "./ShopParts";
import { useStorefront } from "./use-shop";

/**
 * Box › Κατάστημα (proposal §2, option A): a fixed card right below
 * Συνδρομή with four thumbnails and the count of new products. It is absent
 * while the box has no published product (the shop is closed for everyone);
 * a ready order shows on the card as a link to it.
 */
export function ShopBoxCard({ membership }: BoxExtensionProps) {
  const t = useTranslations("Shop");
  const slug = membership.organization.slug;
  const storefront = useStorefront(slug);
  const shop = storefront.data;
  if (!shop || !shop.open || shop.published_count === 0) return null;

  const ready = sortOpenOrders(shop.open_orders).find((order) => order.status === "ready_for_pickup") ?? null;
  const preview = shop.preview.slice(0, 4);
  const pickup = shop.pickup_locations.length === 1 ? shop.pickup_locations[0].name : null;

  return (
    <HubCard>
      <Link href="/box/shop" className="flex flex-col gap-3" data-testid="box-shop-card">
        <span className="flex items-center justify-between gap-2">
          <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t("boxCardTitle")}
          </span>
          {shop.new_count > 0 ? (
            <span className="rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", color: "var(--primary-strong)" }}>
              {t("newCount", { count: shop.new_count })}
            </span>
          ) : null}
        </span>
        <span className="grid grid-cols-4 gap-2">
          {preview.map((item) => (
            <ProductPhoto key={item.id} photo={{ url: item.photo_url }} title={item.title} />
          ))}
        </span>
        <span className="flex items-center justify-between gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
          <span className="truncate">{pickup ? t("boxCardPickupAt", { place: pickup }) : t("boxCardPickup")}</span>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </span>
      </Link>
      {ready ? (
        <Link
          href={`/box/shop/orders/${encodeURIComponent(ready.id)}`}
          className="mt-3 flex min-h-11 items-center justify-between gap-2 rounded-2xl px-4 text-sm font-bold"
          style={{ border: "1px solid var(--primary)", color: "var(--text)" }}
        >
          <span>{t("orderReadyLink", { number: orderReference(ready) })}</span>
          <span aria-hidden="true">›</span>
        </Link>
      ) : null}
    </HubCard>
  );
}
