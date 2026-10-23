import { describe, expect, it } from "vitest";

import { toShopOrder, toShopProduct, type ApiMemberProduct, type ApiOrder } from "./shop";

const NOW = Date.parse("2026-10-23T12:00:00Z");

const product = (overrides: Partial<ApiMemberProduct> = {}): ApiMemberProduct => ({
  id: "p1",
  title: "Box tee",
  category: "Apparel",
  media_ids: [],
  options: { axes: [{ name: "Size", values: ["S", "M"] }] },
  per_person_limit: null,
  all_locations: true,
  location_ids: [],
  published_at: "2026-10-20T09:00:00Z",
  variants: [
    { id: "v1", title: "S", option_values: { Size: "S" }, price_cents: 2500, currency: "EUR", available: "in_stock" },
    { id: "v2", title: "M", option_values: { Size: "M" }, price_cents: 2500, currency: "EUR", available: "sold_out" },
    { id: "v3", title: "L", option_values: { Size: "L" }, price_cents: 2500, currency: "EUR", available: "low" },
  ],
  ...overrides,
});

describe("shop product adapter", () => {
  it("maps member availability to stock states without counts", () => {
    const mapped = toShopProduct(product(), NOW);
    expect(mapped.variants.map((variant) => [variant.stock_status, variant.available])).toEqual([
      ["ok", null],
      ["out", 0],
      ["low", null],
    ]);
  });

  it("marks a product new for 14 days and keeps branch limits", () => {
    expect(toShopProduct(product(), NOW).is_new).toBe(true);
    expect(toShopProduct(product({ published_at: "2026-10-01T09:00:00Z" }), NOW).is_new).toBe(false);
    expect(toShopProduct(product({ all_locations: false, location_ids: ["b1"] }), NOW).pickup_location_ids).toEqual(["b1"]);
    expect(toShopProduct(product(), NOW).pickup_location_ids).toEqual([]);
  });
});

describe("shop order adapter", () => {
  const order: ApiOrder = {
    id: "o1",
    number: 42,
    status: "placed",
    payment_status: "pending_payment",
    payment_mode: "at_pickup",
    pickup_location_id: "b1",
    currency: "EUR",
    subtotal_cents: 2500,
    discount_cents: 250,
    total_cents: 2250,
    placed_at: "2026-10-23T10:00:00Z",
    lines: [{ id: "l1", variant_id: "v1", product_title: "Box tee", variant_title: "S", quantity: 1, total_cents: 2250 }],
  };

  it("names the pickup branch and lets the buyer cancel an unpaid order before pickup", () => {
    const mapped = toShopOrder(order, [{ id: "b1", name: "Κυψέλη", hint: null }]);
    expect(mapped.pickup_location?.name).toBe("Κυψέλη");
    expect(mapped.can_cancel).toBe(true);
    expect(toShopOrder({ ...order, payment_status: "paid" }).can_cancel).toBe(false);
    expect(toShopOrder({ ...order, status: "ready_for_pickup" }).can_cancel).toBe(false);
  });
});
