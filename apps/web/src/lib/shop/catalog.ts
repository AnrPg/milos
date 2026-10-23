import type { ShopOrder, ShopOrderStatus, ShopProductSummary } from "@/api/shop";

import { isSoldOut } from "./variants";

/** The shop grid's filters (Baymard PLP): a category, in stock only, new only. */
export type ShopFilters = { category: string | null; inStockOnly: boolean; newOnly: boolean };

export const NO_FILTERS: ShopFilters = { category: null, inStockOnly: false, newOnly: false };

/** The categories in catalogue order, each once. */
export function shopCategories(products: ShopProductSummary[]) {
  const seen = new Set<string>();
  for (const product of products) {
    const category = product.category?.trim();
    if (category) seen.add(category);
  }
  return [...seen];
}

export function filterProducts(products: ShopProductSummary[], filters: ShopFilters) {
  return products.filter((product) => {
    if (filters.category && product.category?.trim() !== filters.category) return false;
    if (filters.newOnly && !product.is_new) return false;
    if (filters.inStockOnly && product.variants.every(isSoldOut)) return false;
    return true;
  });
}

/** «Φίλτρα (n)» counts what the drawer holds; the category has its own chips. */
export function drawerFilterCount(filters: ShopFilters) {
  return Number(filters.inStockOnly) + Number(filters.newOnly);
}

/** Filters in the URL, so back from a product lands on the same list. */
export function filtersFromParams(params: URLSearchParams): ShopFilters {
  return {
    category: params.get("category")?.trim() || null,
    inStockOnly: params.get("stock") === "1",
    newOnly: params.get("new") === "1",
  };
}

export function filtersToParams(filters: ShopFilters, base: URLSearchParams = new URLSearchParams()) {
  const params = new URLSearchParams(base.toString());
  for (const key of ["category", "stock", "new"]) params.delete(key);
  if (filters.category) params.set("category", filters.category);
  if (filters.inStockOnly) params.set("stock", "1");
  if (filters.newOnly) params.set("new", "1");
  return params;
}

// Orders -------------------------------------------------------------------

/** The order's reference as the desk says it, «K-1042». */
export function orderReference(order: Pick<ShopOrder, "number">) {
  return `K-${order.number}`;
}

export type TimelineStep = { id: "placed" | "ready" | "picked_up" | "cancelled"; state: "done" | "current" | "upcoming"; at: string | null };

/** Placed → ready at the desk → picked up; a cancelled order ends where it stopped. */
export function orderTimeline(order: Pick<ShopOrder, "status" | "placed_at" | "ready_at" | "picked_up_at" | "cancelled_at">): TimelineStep[] {
  if (order.status === "cancelled") {
    return [
      { id: "placed", state: "done", at: order.placed_at },
      ...(order.ready_at ? [{ id: "ready" as const, state: "done" as const, at: order.ready_at }] : []),
      { id: "cancelled", state: "current", at: order.cancelled_at },
    ];
  }
  const reached: Record<ShopOrderStatus, number> = { placed: 0, ready_for_pickup: 1, picked_up: 2, cancelled: 0 };
  const index = reached[order.status];
  const steps: TimelineStep[] = [
    { id: "placed", state: "done", at: order.placed_at },
    { id: "ready", state: index >= 1 ? "done" : "current", at: order.ready_at },
    { id: "picked_up", state: index >= 2 ? "done" : index === 1 ? "current" : "upcoming", at: order.picked_up_at },
  ];
  return steps;
}

/** Ready orders first, then the newest. */
export function sortOpenOrders<T extends Pick<ShopOrder, "status" | "placed_at">>(orders: T[]) {
  return [...orders]
    .filter((order) => order.status === "placed" || order.status === "ready_for_pickup")
    .sort((a, b) => {
      if (a.status !== b.status) return a.status === "ready_for_pickup" ? -1 : 1;
      return b.placed_at.localeCompare(a.placed_at);
    });
}
