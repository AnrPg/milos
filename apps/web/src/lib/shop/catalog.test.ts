import { describe, expect, it } from "vitest";

import type { ShopProductSummary } from "@/api/shop";

import {
  NO_FILTERS,
  drawerFilterCount,
  filterProducts,
  filtersFromParams,
  filtersToParams,
  orderReference,
  orderTimeline,
  shopCategories,
  sortOpenOrders,
} from "./catalog";

const product = (id: string, category: string | null, isNew: boolean, available: number): ShopProductSummary => ({
  id,
  title: id,
  category,
  photos: [],
  options: { axes: [] },
  variants: [{ id: `${id}-v`, title: null, option_values: {}, price_cents: 100, currency: "EUR", stock_status: available > 0 ? "ok" : "out", available }],
  member_discount_applies: false,
  per_person_limit: null,
  is_new: isNew,
  published_at: null,
});

const products = [product("tee", "Ρούχα", true, 3), product("whey", "Συμπληρώματα", false, 0), product("chalk", null, false, 9)];

describe("shop filters", () => {
  it("lists categories once, in catalogue order", () => {
    expect(shopCategories([...products, product("hood", " Ρούχα ", false, 1)])).toEqual(["Ρούχα", "Συμπληρώματα"]);
  });

  it("filters by category, stock and novelty", () => {
    expect(filterProducts(products, NO_FILTERS).map((item) => item.id)).toEqual(["tee", "whey", "chalk"]);
    expect(filterProducts(products, { ...NO_FILTERS, category: "Ρούχα" }).map((item) => item.id)).toEqual(["tee"]);
    expect(filterProducts(products, { ...NO_FILTERS, inStockOnly: true }).map((item) => item.id)).toEqual(["tee", "chalk"]);
    expect(filterProducts(products, { ...NO_FILTERS, newOnly: true }).map((item) => item.id)).toEqual(["tee"]);
    expect(drawerFilterCount({ category: "x", inStockOnly: true, newOnly: true })).toBe(2);
  });

  it("keeps the filters in the URL next to other parameters", () => {
    const params = filtersToParams({ category: "Ρούχα", inStockOnly: true, newOnly: false }, new URLSearchParams("box=kypseli&stock=1"));
    expect(params.toString()).toBe(`box=kypseli&category=${encodeURIComponent("Ρούχα")}&stock=1`);
    expect(filtersFromParams(params)).toEqual({ category: "Ρούχα", inStockOnly: true, newOnly: false });
  });
});

describe("orders", () => {
  const base = { placed_at: "2026-10-23T10:14:00Z", ready_at: null, picked_up_at: null, cancelled_at: null };

  it("names an order the way the desk does", () => {
    expect(orderReference({ number: 1042 })).toBe("K-1042");
  });

  it("walks placed → ready → picked up", () => {
    expect(orderTimeline({ ...base, status: "placed" }).map((step) => step.state)).toEqual(["done", "current", "upcoming"]);
    expect(orderTimeline({ ...base, status: "ready_for_pickup", ready_at: "2026-10-23T16:02:00Z" }).map((step) => step.state)).toEqual(["done", "done", "current"]);
    expect(orderTimeline({ ...base, status: "picked_up" }).map((step) => step.state)).toEqual(["done", "done", "done"]);
  });

  it("ends a cancelled order where it stopped", () => {
    expect(orderTimeline({ ...base, status: "cancelled", cancelled_at: "2026-10-24T09:00:00Z" }).map((step) => step.id)).toEqual(["placed", "cancelled"]);
  });

  it("puts ready orders first and leaves closed ones out", () => {
    const orders = [
      { id: "a", status: "placed" as const, placed_at: "2026-10-23T09:00:00Z" },
      { id: "b", status: "ready_for_pickup" as const, placed_at: "2026-10-20T09:00:00Z" },
      { id: "c", status: "picked_up" as const, placed_at: "2026-10-22T09:00:00Z" },
      { id: "d", status: "placed" as const, placed_at: "2026-10-23T11:00:00Z" },
    ];
    expect(sortOpenOrders(orders).map((order) => order.id)).toEqual(["b", "d", "a"]);
  });
});
